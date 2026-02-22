import AppKit
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
    var appState = AppState()
    private(set) var iconAnimator = IconAnimator()
    private(set) var configStore: ConfigStore?
    private var fileWatcher: FileWatcher?
    private var eventLoopTask: Task<Void, Never>?
    private var isStarted = false
    private var musicLibraryIndex: MusicLibraryIndex?
    private var tasks: [any FileTask] = []
    private let errorCollector = ErrorCollector()
    private var configFileWatcher: ConfigFileWatcher?
    private var sleepWakeTask: Task<Void, Never>?
    private var wakeObserverTask: Task<Void, Never>?

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

        // 4. Build music library index and configure audio pipeline
        let audioConfig = store.config.audio
        let musicDirectoryPath = NSString(string: audioConfig.destinationPath).expandingTildeInPath
        let musicDirectoryURL = URL(fileURLWithPath: musicDirectoryPath, isDirectory: true)

        let libraryIndex = MusicLibraryIndex()
        self.musicLibraryIndex = libraryIndex
        await libraryIndex.build(from: musicDirectoryURL)

        // 5. Check ffmpeg availability
        let ffmpegPath = FFmpegLocator.locate()
        appState.ffmpegAvailable = (ffmpegPath != nil)

        if let ffmpegPath {
            AppLogger.shared.info("ffmpeg found", context: ["path": ffmpegPath.path])
        } else {
            AppLogger.shared.warn("ffmpeg not found — audio conversion disabled. Install via: brew install ffmpeg")
        }

        let conversionPool: ConversionPool? = ffmpegPath != nil ? ConversionPool() : nil

        // 6. Build CSV writer for low-quality file logging
        let appSupportPath = NSString(string: "~/Library/Application Support/OhMyClaw").expandingTildeInPath
        let csvLogURL = URL(fileURLWithPath: appSupportPath, isDirectory: true)
            .appendingPathComponent("low_quality_log.csv")
        let csvWriter = CSVWriter(fileURL: csvLogURL)

        // 7. Parse quality cutoff from config
        let qualityCutoff = QualityTier(rawValue: audioConfig.qualityCutoff) ?? .mp3_320

        let audioTask = AudioTask(
            identifier: AudioFileIdentifier(),
            metadataReader: AudioMetadataReader(),
            libraryIndex: libraryIndex,
            config: audioConfig,
            ffmpegPath: ffmpegPath,
            conversionPool: conversionPool,
            qualityCutoff: qualityCutoff,
            csvWriter: csvWriter
        )
        if audioConfig.enabled {
            tasks.append(audioTask)
        }

        AppLogger.shared.info("Audio pipeline ready",
            context: ["enabled": "\(audioConfig.enabled)"])

        // 8. Configure PDF classification pipeline
        let pdfConfig = store.config.pdf
        let openaiClient = OpenAIClient(apiKey: pdfConfig.openaiApiKey, modelName: pdfConfig.openaiModel)
        let apiKeyConfigured = !pdfConfig.openaiApiKey.isEmpty
        appState.openaiApiKeyConfigured = apiKeyConfigured

        if apiKeyConfigured {
            AppLogger.shared.info("OpenAI API key configured", context: ["model": pdfConfig.openaiModel])
        } else {
            AppLogger.shared.warn("OpenAI API key not configured — add your API key to config.json in the pdf.openaiApiKey field")
        }

        let pdfTask = PDFTask(
            identifier: PDFFileIdentifier(),
            textExtractor: PDFTextExtractor(),
            client: openaiClient,
            destinationPath: pdfConfig.destinationPath,
            isEnabled: pdfConfig.enabled
        )
        if pdfConfig.enabled {
            tasks.append(pdfTask)
        }

        AppLogger.shared.info("PDF pipeline ready",
            context: ["enabled": "\(pdfConfig.enabled)"])

        // 9. Start file watcher if monitoring is enabled (defaults to true)
        if appState.monitoringState != .paused {
            await startMonitoring()
        }

        // 10. Start config file watcher for hot-reload
        startConfigFileWatcher()

        // 11. Subscribe to sleep/wake notifications
        observeSleepWake()
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
                    await self.errorCollector.report(
                        category: .fileDisappeared,
                        file: filename,
                        message: "File was removed before processing could complete"
                    )
                    continue
                }

                // Log the detection
                AppLogger.shared.info("File detected",
                    context: [
                        "file": fileURL.lastPathComponent,
                        "size": "\(fileURL.fileSize ?? 0) bytes"
                    ])

                // Track processing count
                self.appState.processingCount += 1
                self.onProcessingCountChanged()
                defer {
                    self.appState.processingCount -= 1
                    self.onProcessingCountChanged()
                }

                // Route through registered tasks
                var handled = false
                for task in self.tasks where task.isEnabled && task.canHandle(file: fileURL) {
                    do {
                        let result = try await task.process(file: fileURL)
                        switch result {
                        case .processed(let action):
                            AppLogger.shared.info("File processed",
                                context: ["file": fileURL.lastPathComponent, "task": task.id, "action": action])
                        case .skipped(let reason):
                            AppLogger.shared.info("File skipped",
                                context: ["file": fileURL.lastPathComponent, "task": task.id, "reason": reason])
                        case .duplicate(let title, let artist):
                            AppLogger.shared.info("Duplicate deleted",
                                context: ["file": fileURL.lastPathComponent, "task": task.id, "title": title, "artist": artist])
                        case .error(let description):
                            AppLogger.shared.error("Processing error",
                                context: ["file": fileURL.lastPathComponent, "task": task.id, "error": description])
                            await self.errorCollector.report(
                                category: self.errorCategory(for: task.id),
                                file: fileURL.lastPathComponent,
                                message: description
                            )
                        }
                        handled = true
                        break
                    } catch {
                        self.appState.lastError = error.localizedDescription
                        AppLogger.shared.error("Task failed",
                            context: ["file": fileURL.lastPathComponent, "task": task.id, "error": error.localizedDescription])
                        await self.errorCollector.report(
                            category: self.errorCategory(for: task.id),
                            file: fileURL.lastPathComponent,
                            message: error.localizedDescription
                        )
                    }
                }

                if !handled {
                    AppLogger.shared.debug("No task handled file",
                        context: ["file": fileURL.lastPathComponent])
                }
            }
        }
    }

    /// Stop monitoring — cancel the event loop and stop the file watcher.
    private func stopMonitoring() {
        eventLoopTask?.cancel()
        eventLoopTask = nil
        fileWatcher?.stop()
        fileWatcher = nil
        stopConfigFileWatcher()
        iconAnimator.stopAnimating()
        AppLogger.shared.info("File monitoring stopped")
    }

    /// Pause monitoring — stops the file watcher but lets in-flight tasks finish.
    func pauseMonitoring() {
        appState.monitoringState = .paused
        fileWatcher?.stop()
        fileWatcher = nil
        // Do NOT cancel eventLoopTask — let in-flight iterations finish
        AppLogger.shared.info("Monitoring paused by user — in-flight tasks will complete")
    }

    /// Resume monitoring — restarts file watcher and event loop.
    func resumeMonitoring() async {
        appState.monitoringState = .idle
        await startMonitoring()
        updateMonitoringState()
        AppLogger.shared.info("Monitoring resumed by user")
    }

    /// Called when the monitoring toggle changes.
    /// Starts or stops the FileWatcher accordingly.
    func toggleMonitoring(_ isEnabled: Bool) async {
        if isEnabled {
            await resumeMonitoring()
        } else {
            pauseMonitoring()
        }
    }

    /// Update icon animator and monitoring state based on current processing count.
    private func onProcessingCountChanged() {
        if appState.processingCount > 0 && iconAnimator.currentFrame == 0 {
            iconAnimator.startAnimating()
        } else if appState.processingCount <= 0 {
            iconAnimator.stopAnimating()
        }
        appState.animatedIconName = iconAnimator.currentIconName
        updateMonitoringState()
    }

    /// Map a FileTask's id to an ErrorCategory for error notification routing.
    private func errorCategory(for taskId: String) -> ErrorCategory {
        switch taskId {
        case "audio":
            return .audioConversion
        case "pdf":
            return .pdfClassification
        default:
            return .general
        }
    }

    /// Derive monitoringState from current processing count and error state.
    private func updateMonitoringState() {
        if case .paused = appState.monitoringState { return }
        if let error = appState.lastError {
            appState.monitoringState = .error(message: error)
        } else if appState.processingCount > 0 {
            appState.monitoringState = .processing(count: appState.processingCount)
        } else {
            appState.monitoringState = .idle
        }
    }

    // MARK: - Config File Watcher

    /// Start watching config.json for external changes (hot-reload).
    private func startConfigFileWatcher() {
        guard let configURL = configStore?.configFileURL else { return }

        let watcher = ConfigFileWatcher(fileURL: configURL)
        self.configFileWatcher = watcher

        watcher.start { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleConfigChange()
            }
        }

        AppLogger.shared.info("Config file watcher started",
            context: ["path": configURL.path])
    }

    /// Stop watching the config file.
    private func stopConfigFileWatcher() {
        configFileWatcher?.stop()
        configFileWatcher = nil
    }

    /// Handle a detected change to the config file.
    /// Called by ConfigFileWatcher after debounce, on @MainActor.
    private func handleConfigChange() async {
        guard let store = configStore else { return }

        let result = store.reload()

        switch result {
        case .unchanged:
            AppLogger.shared.debug("Config file changed but content unchanged")

        case .updated:
            AppLogger.shared.info("Config reloaded — rebuilding task pipeline")
            NotificationManager.shared.notifyConfigReloaded()
            rebuildTaskPipeline()

        case .invalid(let errors):
            AppLogger.shared.warn("Config reload failed — keeping previous config",
                context: ["errors": errors.joined(separator: "; ")])
            for error in errors {
                await errorCollector.report(
                    category: .configReload,
                    file: "config.json",
                    message: error
                )
            }
        }
    }

    /// Rebuild the task pipeline with the current config.
    /// In-flight tasks keep their old config (value-type capture).
    /// Only affects which tasks handle FUTURE files.
    private func rebuildTaskPipeline() {
        guard let store = configStore else { return }
        let config = store.config

        var newTasks: [any FileTask] = []

        // Rebuild audio task
        let audioConfig = config.audio
        let musicDirectoryPath = NSString(string: audioConfig.destinationPath).expandingTildeInPath
        let musicDirectoryURL = URL(fileURLWithPath: musicDirectoryPath, isDirectory: true)

        let ffmpegPath = FFmpegLocator.locate()
        appState.ffmpegAvailable = (ffmpegPath != nil)
        let conversionPool: ConversionPool? = ffmpegPath != nil ? ConversionPool() : nil

        let appSupportPath = NSString(string: "~/Library/Application Support/OhMyClaw").expandingTildeInPath
        let csvLogURL = URL(fileURLWithPath: appSupportPath, isDirectory: true)
            .appendingPathComponent("low_quality_log.csv")
        let csvWriter = CSVWriter(fileURL: csvLogURL)

        let qualityCutoff = QualityTier(rawValue: audioConfig.qualityCutoff) ?? .mp3_320

        // Rebuild music library index for the possibly-new destination path
        if let libraryIndex = musicLibraryIndex {
            Task {
                await libraryIndex.build(from: musicDirectoryURL)
            }
        }

        let audioTask = AudioTask(
            identifier: AudioFileIdentifier(),
            metadataReader: AudioMetadataReader(),
            libraryIndex: musicLibraryIndex ?? MusicLibraryIndex(),
            config: audioConfig,
            ffmpegPath: ffmpegPath,
            conversionPool: conversionPool,
            qualityCutoff: qualityCutoff,
            csvWriter: csvWriter
        )
        if audioConfig.enabled {
            newTasks.append(audioTask)
        }

        // Rebuild PDF task
        let pdfConfig = config.pdf
        let openaiClient = OpenAIClient(apiKey: pdfConfig.openaiApiKey, modelName: pdfConfig.openaiModel)
        appState.openaiApiKeyConfigured = !pdfConfig.openaiApiKey.isEmpty

        let pdfTask = PDFTask(
            identifier: PDFFileIdentifier(),
            textExtractor: PDFTextExtractor(),
            client: openaiClient,
            destinationPath: pdfConfig.destinationPath,
            isEnabled: pdfConfig.enabled
        )
        if pdfConfig.enabled {
            newTasks.append(pdfTask)
        }

        self.tasks = newTasks

        // Reconfigure logger if logging config changed
        let logConfig = config.logging
        AppLogger.shared.configure(
            maxFileSizeMB: logConfig.maxFileSizeMB,
            maxRotatedFiles: logConfig.maxRotatedFiles,
            level: logConfig.level
        )

        AppLogger.shared.info("Task pipeline rebuilt",
            context: [
                "audioEnabled": "\(config.audio.enabled)",
                "pdfEnabled": "\(config.pdf.enabled)"
            ])
    }

    // MARK: - Sleep/Wake Recovery

    /// Subscribe to macOS sleep/wake notifications using async sequences.
    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter

        // Will Sleep observer
        sleepWakeTask = Task { [weak self] in
            for await _ in center.notifications(named: NSWorkspace.willSleepNotification) {
                guard let self else { break }
                await self.handleWillSleep()
            }
        }

        // Did Wake observer
        wakeObserverTask = Task { [weak self] in
            for await _ in center.notifications(named: NSWorkspace.didWakeNotification) {
                guard let self else { break }
                await self.handleDidWake()
            }
        }

        AppLogger.shared.info("Sleep/wake observers registered")
    }

    /// System is about to sleep. Tear down all watchers and flush pending errors.
    private func handleWillSleep() async {
        AppLogger.shared.info("System will sleep — tearing down watchers and event loop")

        // Flush any pending error batches before sleeping
        await errorCollector.flushAll()

        // Cancel the event loop (stops processing new events)
        eventLoopTask?.cancel()
        eventLoopTask = nil

        // Stop the FSEvents file watcher
        fileWatcher?.stop()
        fileWatcher = nil

        // Stop the config file watcher
        stopConfigFileWatcher()

        AppLogger.shared.info("Teardown complete — ready for sleep")
    }

    /// System woke from sleep. Restart monitoring if it was enabled before sleep.
    private func handleDidWake() async {
        AppLogger.shared.info("System woke — re-establishing monitoring")

        // Reset error cooldowns so fresh errors are reported immediately
        await errorCollector.resetCooldowns()

        // Only restart if monitoring was enabled before sleep
        let shouldRestart: Bool
        if case .paused = appState.monitoringState {
            shouldRestart = false
        } else {
            shouldRestart = true
        }

        guard shouldRestart else {
            AppLogger.shared.info("Monitoring was paused before sleep — not restarting")
            return
        }

        // Restart file monitoring (creates fresh FileWatcher + event loop + scans ~/Downloads)
        await startMonitoring()

        // Restart config file watcher
        startConfigFileWatcher()

        AppLogger.shared.info("Monitoring resumed after sleep/wake")
    }

}
