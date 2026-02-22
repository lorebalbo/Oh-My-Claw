import SwiftUI

/// Observable app-wide state shared between UI and services.
/// Uses @Observable (Observation framework, macOS 14+).
@Observable
final class AppState {
    /// Whether the file watcher is actively monitoring ~/Downloads.
    /// Defaults to true — monitoring auto-starts on app launch.
    var isMonitoring: Bool = true

    /// Whether ffmpeg is available on the system.
    /// Checked once at launch; defaults to true until verified.
    var ffmpegAvailable: Bool = true
}
