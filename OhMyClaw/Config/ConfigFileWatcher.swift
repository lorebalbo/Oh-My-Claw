import Foundation

/// Watches a single file (config.json) for changes using DispatchSource.
/// Handles atomic saves (inode replacement) by re-opening the file descriptor
/// when .delete or .rename events are detected.
///
/// Usage:
/// ```
/// let watcher = ConfigFileWatcher(fileURL: configURL)
/// watcher.start { print("config changed") }
/// // later...
/// watcher.stop()
/// ```
final class ConfigFileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.ohmyclaw.config-watcher", qos: .utility)
    private var fileDescriptor: Int32 = -1
    private var reloadTask: Task<Void, Never>?

    /// Debounce interval in seconds. Multiple rapid writes (e.g., staged editor saves)
    /// are collapsed into a single onChange invocation.
    private let debounceInterval: TimeInterval = 0.5

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Start watching the config file for changes.
    /// - Parameter onChange: Called after debounce when the file changes.
    ///   The caller is responsible for dispatching to the correct actor/thread.
    func start(onChange: @escaping @Sendable () -> Void) {
        stop() // Clean up any previous session

        fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            AppLogger.shared.error("ConfigFileWatcher: failed to open file descriptor",
                context: ["path": fileURL.path])
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data

            if flags.contains(.delete) || flags.contains(.rename) {
                // File was replaced by an atomic save (new inode).
                // Close old fd, wait briefly for the new file, then re-attach.
                AppLogger.shared.debug("ConfigFileWatcher: file replaced (atomic save), restarting")
                self.restart(onChange: onChange)
            } else {
                // In-place write — debounce and notify
                self.scheduleDebounce(onChange: onChange)
            }
        }

        source.setCancelHandler { [fd = fileDescriptor] in
            close(fd)
        }

        source.resume()
        self.source = source

        AppLogger.shared.info("ConfigFileWatcher started",
            context: ["path": fileURL.path])
    }

    /// Stop watching and release all resources.
    func stop() {
        reloadTask?.cancel()
        reloadTask = nil

        if let source {
            source.cancel()
            self.source = nil
        }
        // Note: file descriptor is closed by the source's cancelHandler.
        // If source was never created but fd was opened, close it manually.
        if fileDescriptor >= 0 && source == nil {
            close(fileDescriptor)
        }
        fileDescriptor = -1
    }

    // MARK: - Private

    /// Debounce rapid change events into a single onChange call.
    /// Resets the timer on each new event; only fires after 500ms of quiet.
    private func scheduleDebounce(onChange: @escaping @Sendable () -> Void) {
        reloadTask?.cancel()
        reloadTask = Task { [debounceInterval] in
            try? await Task.sleep(for: .seconds(debounceInterval))
            guard !Task.isCancelled else { return }
            onChange()
        }
    }

    /// Re-open the file after an atomic save replaced the inode.
    /// Waits 100ms for the new file to appear, then calls start() to re-attach.
    private func restart(onChange: @escaping @Sendable () -> Void) {
        // Cancel the current source (which closes the old fd via cancelHandler)
        source?.cancel()
        source = nil
        fileDescriptor = -1

        // Wait briefly for the new file to be fully written, then re-attach
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.start(onChange: onChange)
            // Also fire the onChange since the file content changed
            self?.scheduleDebounce(onChange: onChange)
        }
    }

    deinit {
        stop()
    }
}
