import Foundation
import CoreServices

/// A file event from FSEvents with path and event flags.
struct FileEvent: Sendable {
    let url: URL
    let flags: FSEventStreamEventFlags
    let timestamp: Date

    /// Whether this event represents a file being created or modified (not removed).
    var isFileAppeared: Bool {
        let created = flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
        let modified = flags & UInt32(kFSEventStreamEventFlagItemModified) != 0
        let renamed = flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
        let isFile = flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
        return isFile && (created || modified || renamed)
    }

    var isFileRemoved: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
    }
}

/// Monitors ~/Downloads for new files using FSEvents.
/// Produces an AsyncStream of file URLs after debounce + stability checks.
/// Filters out temporary downloads and hidden files.
///
/// Usage:
/// ```
/// let watcher = FileWatcher()
/// watcher.start()
/// for await url in watcher.events {
///     // url is a stable, non-temp file ready for processing
/// }
/// ```
final class FileWatcher: @unchecked Sendable {
    /// Stream of file URLs that have passed debounce + stability checks.
    private(set) var events: AsyncStream<URL>!
    private var continuation: AsyncStream<URL>.Continuation?

    private let watchedDirectory: URL
    private var stream: FSEventStreamRef?
    private let eventQueue = DispatchQueue(label: "com.ohmyclaw.fsevents", qos: .utility)
    private let debouncer: FileDebouncer

    /// - Parameters:
    ///   - directory: Directory to watch. Defaults to ~/Downloads.
    ///   - debounceSeconds: Seconds to wait after last event before processing. Default: 3.0.
    ///   - stabilityCheckInterval: Seconds between file size reads for stability check. Default: 0.5.
    init(
        directory: URL = .downloadsDirectory,
        debounceSeconds: Double = 3.0,
        stabilityCheckInterval: Double = 0.5
    ) {
        self.watchedDirectory = directory
        self.debouncer = FileDebouncer(
            debounceInterval: debounceSeconds,
            stabilityCheckInterval: stabilityCheckInterval
        )

        self.events = AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    /// Start monitoring the watched directory.
    /// Also scans for existing files and emits them.
    func start() {
        startFSEventStream()
    }

    /// Scan existing files in ~/Downloads and emit any that pass filtering.
    /// Called on launch to process files that arrived while the app wasn't running.
    func scanExistingFiles() async {
        guard let enumerator = FileManager.default.enumerator(
            at: watchedDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        var filesToProcess: [URL] = []
        for case let fileURL as URL in enumerator {
            guard !fileURL.shouldBeIgnored,
                  !fileURL.isDirectory else { continue }
            filesToProcess.append(fileURL)
        }

        // Emit existing files (they're already stable — no debounce needed)
        for url in filesToProcess {
            continuation?.yield(url)
        }
    }

    /// Stop monitoring and clean up FSEvents resources.
    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        debouncer.cancelAll()
    }

    // MARK: - Private

    private func startFSEventStream() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [watchedDirectory.path as CFString] as CFArray
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

            for i in 0..<numEvents {
                let event = FileEvent(
                    url: URL(fileURLWithPath: paths[i]),
                    flags: eventFlags[i],
                    timestamp: Date()
                )
                watcher.handleRawEvent(event)
            }
        }

        guard let fsStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // 500ms latency for batching raw events before callback fires
            flags
        ) else {
            return
        }

        self.stream = fsStream
        FSEventStreamSetDispatchQueue(fsStream, eventQueue)
        FSEventStreamStart(fsStream)
    }

    private func handleRawEvent(_ event: FileEvent) {
        // Only care about file-appeared events
        guard event.isFileAppeared else { return }

        // Filter: ignore hidden files and temp downloads
        guard !event.url.shouldBeIgnored else { return }

        // Filter: top-level only — ignore files in subdirectories
        let parentDir = event.url.deletingLastPathComponent().standardizedFileURL
        let watchedDir = watchedDirectory.standardizedFileURL
        guard parentDir == watchedDir else { return }

        // Debounce: reset timer for this path, then stability check
        Task {
            await debouncer.debounce(url: event.url) { [weak self] stableURL in
                self?.continuation?.yield(stableURL)
            }
        }
    }
}

// MARK: - FileDebouncer

/// Per-file debounce with file size stability verification.
/// Each file gets its own timer. New events for the same path reset the timer.
/// After the debounce interval, verifies file size stability before emitting.
actor FileDebouncer {
    private var pendingTasks: [String: Task<Void, Never>] = [:]
    private let debounceInterval: Double
    private let stabilityCheckInterval: Double

    init(debounceInterval: Double = 3.0, stabilityCheckInterval: Double = 0.5) {
        self.debounceInterval = debounceInterval
        self.stabilityCheckInterval = stabilityCheckInterval
    }

    /// Debounce a file event. If the same file fires again within the interval,
    /// the previous timer is cancelled and a new one starts.
    func debounce(url: URL, action: @escaping @Sendable (URL) -> Void) {
        let key = url.path
        pendingTasks[key]?.cancel()

        pendingTasks[key] = Task { [debounceInterval, stabilityCheckInterval] in
            // Wait for debounce interval
            try? await Task.sleep(for: .seconds(debounceInterval))
            guard !Task.isCancelled else { return }

            // File size stability check: two reads separated by interval must match
            guard let size1 = url.fileSize else { return } // file disappeared
            try? await Task.sleep(for: .seconds(stabilityCheckInterval))
            guard !Task.isCancelled else { return }
            guard let size2 = url.fileSize else { return } // file disappeared
            guard size1 == size2, size1 > 0 else {
                // File still changing or empty — re-debounce
                debounce(url: url, action: action)
                return
            }

            // File is stable — emit it
            action(url)
            // Clean up tracking
            self.removePending(key: key)
        }
    }

    /// Cancel all pending debounce timers.
    nonisolated func cancelAll() {
        Task {
            await _cancelAll()
        }
    }

    private func _cancelAll() {
        for task in pendingTasks.values {
            task.cancel()
        }
        pendingTasks.removeAll()
    }

    private func removePending(key: String) {
        pendingTasks.removeValue(forKey: key)
    }
}
