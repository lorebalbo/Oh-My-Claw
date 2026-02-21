import Foundation
import SwiftUI

/// Central coordinator that owns and connects all services.
///
/// Lifecycle:
/// 1. App launches → AppCoordinator initializes
/// 2. `start()` called from `.task` modifier on MenuBarView
/// 3. ConfigStore loads config → Logger configured → FileWatcher starts
/// 4. Existing files in ~/Downloads scanned and emitted
/// 5. New file events processed through the event loop
/// 6. Toggle off → FileWatcher stops; Toggle on → FileWatcher restarts
@MainActor
@Observable
final class AppCoordinator {
    let appState = AppState()
    private var configStore: ConfigStore?
    private var fileWatcher: FileWatcher?
    private var eventLoopTask: Task<Void, Never>?
    private var isStarted = false

    /// Start all services. Called once from the UI on app launch.
    func start() async {
        guard !isStarted else { return }
        isStarted = true

        // 1. Load configuration
        let store = ConfigStore()
        store.load()
        self.configStore = store

        // 2. Notify user about config validation errors
        if !store.validationErrors.isEmpty {
            AppLogger.shared.warn("Config validation failed, using defaults",
                context: ["errors": store.validationErrors.joined(separator: "; ")])
            NotificationManager.shared.notifyConfigError(store.validationErrors)
        }

        // 3. Configure logger from loaded config
        let logConfig = store.config.logging
        AppLogger.shared.configure(
            maxFileSizeMB: logConfig.maxFileSizeMB,
            maxRotatedFiles: logConfig.maxRotatedFiles,
            level: logConfig.level
        )

        AppLogger.shared.info("Oh My Claw started",
            context: ["configPath": store.config.logging.level])

        // 4. Start file watcher if monitoring is enabled (defaults to true)
        if appState.isMonitoring {
            await startMonitoring()
        }
    }

    /// Start the file watcher and event processing loop.
    private func startMonitoring() async {
        guard let config = configStore?.config else { return }

        let watcher = FileWatcher(
            debounceSeconds: config.watcher.debounceSeconds,
            stabilityCheckInterval: config.watcher.stabilityCheckInterval
        )
        self.fileWatcher = watcher

        AppLogger.shared.info("File monitoring started",
            context: ["directory": "~/Downloads",
                      "debounce": "\(config.watcher.debounceSeconds)s"])

        // Start FSEvents stream
        watcher.start()

        // Scan existing files in ~/Downloads
        AppLogger.shared.info("Scanning existing files in ~/Downloads")
        await watcher.scanExistingFiles()

        // Start the event processing loop
        eventLoopTask = Task { [weak self] in
            for await fileURL in watcher.events {
                guard let self = self else { break }

                // Check if file still exists (it may have disappeared)
                guard fileURL.fileExists else {
                    let filename = fileURL.lastPathComponent
                    AppLogger.shared.warn("File disappeared before processing",
                        context: ["file": filename])
                    NotificationManager.shared.notifyFileDisappeared(filename: filename)
                    continue
                }

                // Log the detection
                AppLogger.shared.info("File detected",
                    context: [
                        "file": fileURL.lastPathComponent,
                        "size": "\(fileURL.fileSize ?? 0) bytes"
                    ])

                // TODO: Phase 2+ — route file to appropriate task (audio, PDF)
                // For Phase 1, we only detect and log. Task routing comes in Phase 2.
            }
        }
    }

    /// Stop monitoring — cancel the event loop and stop the file watcher.
    private func stopMonitoring() {
        eventLoopTask?.cancel()
        eventLoopTask = nil
        fileWatcher?.stop()
        fileWatcher = nil
        AppLogger.shared.info("File monitoring stopped")
    }

    /// Called when the monitoring toggle changes.
    /// Starts or stops the FileWatcher accordingly.
    func toggleMonitoring(_ isEnabled: Bool) async {
        appState.isMonitoring = isEnabled
        if isEnabled {
            AppLogger.shared.info("Monitoring enabled by user")
            await startMonitoring()
        } else {
            AppLogger.shared.info("Monitoring disabled by user")
            stopMonitoring()
        }
    }
}
