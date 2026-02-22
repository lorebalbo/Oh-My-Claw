import SwiftUI

/// Represents the current monitoring lifecycle state.
/// Drives the menu bar icon appearance and status text.
enum MonitoringState: Equatable {
    case idle
    case processing(count: Int)
    case paused
    case error(message: String)

    var statusText: String {
        switch self {
        case .idle: return "Idle"
        case .processing(let count): return "Processing \(count) file\(count == 1 ? "" : "s")"
        case .paused: return "Paused"
        case .error(let message): return "Error: \(message)"
        }
    }
}

/// Observable app-wide state shared between UI and services.
/// Uses @Observable (Observation framework, macOS 14+).
@Observable
final class AppState {
    /// Current monitoring lifecycle state.
    var monitoringState: MonitoringState = .idle

    /// Number of files currently being processed.
    var processingCount: Int = 0

    /// Last error message, if any.
    var lastError: String? = nil

    /// SF Symbol name updated by IconAnimator during processing.
    var animatedIconName: String = "arrow.down.doc"

    /// Whether ffmpeg is available on the system.
    /// Checked once at launch; defaults to true until verified.
    var ffmpegAvailable: Bool = true

    /// Whether the OpenAI API key is configured for PDF classification.
    /// Checked at launch by validating pdf.openaiApiKey is non-empty.
    var openaiApiKeyConfigured: Bool = true

    /// The SF Symbol name to display in the menu bar, based on current state.
    var menuBarIcon: String {
        switch monitoringState {
        case .idle: return "arrow.down.doc"
        case .processing: return animatedIconName
        case .paused: return "arrow.down.doc"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// Symbol rendering mode — hierarchical when paused, monochrome otherwise.
    var iconRenderingMode: SymbolRenderingMode {
        if case .paused = monitoringState { return .hierarchical }
        return .monochrome
    }

    /// Whether monitoring is active (not paused).
    var isActive: Bool {
        monitoringState != .paused
    }
}
