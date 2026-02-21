import Foundation

/// Structured JSON-lines logger with rotating file output.
///
/// Writes one JSON object per line to ~/Library/Logs/OhMyClaw/ohmyclaw.log.
/// Rotates when the file reaches maxFileSize (default 10MB).
/// Keeps at most maxRotatedFiles (default 3) old log files.
///
/// Log format: {"ts":"2026-02-21T10:30:00Z","level":"info","msg":"File detected","ctx":{"file":"song.mp3"}}
///
/// Thread-safe: all writes are serialized on a private DispatchQueue.
final class AppLogger: Sendable {
    /// Shared singleton instance. Configured at app startup.
    static let shared = AppLogger()

    enum Level: String, Codable, Comparable, Sendable {
        case debug
        case info
        case warn
        case error

        private var order: Int {
            switch self {
            case .debug: return 0
            case .info: return 1
            case .warn: return 2
            case .error: return 3
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.order < rhs.order
        }
    }

    /// A single JSON-lines log entry.
    private struct LogEntry: Codable {
        let ts: String
        let level: String
        let msg: String
        let ctx: [String: String]?
    }

    private let logDirectory: URL
    private let logFileName = "ohmyclaw.log"
    private let queue = DispatchQueue(label: "com.ohmyclaw.logger", qos: .utility)
    private let dateFormatter: ISO8601DateFormatter

    // Configurable via configure()
    private var maxFileSize: Int64 = 10 * 1024 * 1024  // 10MB
    private var maxRotatedFiles: Int = 3
    private var minLevel: Level = .info

    private var logFileURL: URL {
        logDirectory.appendingPathComponent(logFileName)
    }

    init() {
        self.logDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/OhMyClaw", isDirectory: true)
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        ensureLogDirectory()
    }

    /// Configure logger settings (called after config is loaded).
    /// Thread-safe — configuration is applied on the logger's serial queue.
    func configure(maxFileSizeMB: Int, maxRotatedFiles: Int, level: String) {
        queue.sync {
            self.maxFileSize = Int64(maxFileSizeMB) * 1024 * 1024
            self.maxRotatedFiles = maxRotatedFiles
            self.minLevel = Level(rawValue: level.lowercased()) ?? .info
        }
    }

    // MARK: - Public Logging Methods

    func debug(_ message: String, context: [String: String]? = nil) {
        log(.debug, message, context: context)
    }

    func info(_ message: String, context: [String: String]? = nil) {
        log(.info, message, context: context)
    }

    func warn(_ message: String, context: [String: String]? = nil) {
        log(.warn, message, context: context)
    }

    func error(_ message: String, context: [String: String]? = nil) {
        log(.error, message, context: context)
    }

    // MARK: - Core

    private func log(_ level: Level, _ message: String, context: [String: String]?) {
        queue.async { [self] in
            guard level >= minLevel else { return }

            let entry = LogEntry(
                ts: dateFormatter.string(from: Date()),
                level: level.rawValue,
                msg: message,
                ctx: context?.isEmpty == true ? nil : context
            )

            guard let data = try? JSONEncoder().encode(entry),
                  var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"

            rotateIfNeeded()
            appendToFile(line)
        }
    }

    // MARK: - File Operations

    private func ensureLogDirectory() {
        if !FileManager.default.fileExists(atPath: logDirectory.path) {
            try? FileManager.default.createDirectory(
                at: logDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func appendToFile(_ line: String) {
        let fileURL = logFileURL
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func rotateIfNeeded() {
        let fileURL = logFileURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attrs[.size] as? Int64,
              fileSize >= maxFileSize else {
            return
        }

        // Rotate: delete oldest, shift existing, rename current
        // ohmyclaw.log.3 (oldest, delete)
        // ohmyclaw.log.2 → ohmyclaw.log.3
        // ohmyclaw.log.1 → ohmyclaw.log.2
        // ohmyclaw.log   → ohmyclaw.log.1

        let fm = FileManager.default

        // Delete the oldest rotated file if it exceeds retention
        let oldestURL = logDirectory.appendingPathComponent("\(logFileName).\(maxRotatedFiles)")
        try? fm.removeItem(at: oldestURL)

        // Shift existing rotated files up by one
        for i in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
            let source = logDirectory.appendingPathComponent("\(logFileName).\(i)")
            let dest = logDirectory.appendingPathComponent("\(logFileName).\(i + 1)")
            if fm.fileExists(atPath: source.path) {
                try? fm.moveItem(at: source, to: dest)
            }
        }

        // Rename current log to .1
        let rotatedURL = logDirectory.appendingPathComponent("\(logFileName).1")
        try? fm.moveItem(at: fileURL, to: rotatedURL)
    }
}
