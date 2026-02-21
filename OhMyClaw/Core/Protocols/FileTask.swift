import Foundation

/// Result of processing a file through a task pipeline.
enum TaskResult: Sendable {
    case processed(action: String)
    case skipped(reason: String)
    case duplicate(title: String, artist: String)
    case error(description: String)
}

/// Protocol that all file task modules implement (audio, PDF, etc.).
/// Each task declares what files it can handle and processes them through
/// a pipeline of steps.
///
/// New file types are added by creating a new struct conforming to FileTask
/// and registering it — zero changes to existing code.
protocol FileTask: Sendable {
    /// Unique identifier for this task (e.g., "audio", "pdf").
    var id: String { get }

    /// Human-readable name shown in logs and UI.
    var displayName: String { get }

    /// Whether this task is currently enabled.
    var isEnabled: Bool { get }

    /// Check if this task can handle the given file (by extension, UTI, etc.).
    func canHandle(file: URL) -> Bool

    /// Process the file through the full task pipeline.
    /// Returns a result indicating what happened.
    func process(file: URL) async throws -> TaskResult
}
