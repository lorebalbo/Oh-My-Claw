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
    private var configStore: ConfigStore?
    private var fileWatcher: FileWatcher?
    private var eventLoopTask: Task<Void, Never>?
    private var isStarted = false
    private var musicLibraryIndex: MusicLibraryIndex?
    private var tasks: [any FileTask] = []

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
                        }
                        handled = true
                        break
                    } catch {
                        AppLogger.shared.error("Task failed",
                            context: ["file": fileURL.lastPathComponent, "task": task.id, "error": error.localizedDescription])
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
