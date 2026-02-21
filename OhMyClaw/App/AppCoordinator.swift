import Foundation

/// Central coordinator that owns and wires all services.
/// Stub implementation — fully wired in Plan 01-04.
@MainActor
@Observable
final class AppCoordinator {
    var appState = AppState()

    /// Start all services and begin monitoring.
    /// Will be implemented in Plan 01-04 to wire FileWatcher, ConfigStore, Logger.
    func start() async {
        // TODO: Plan 01-04 — initialize ConfigStore, Logger, FileWatcher
        // TODO: Plan 01-04 — scan existing files in ~/Downloads
        // TODO: Plan 01-04 — begin async event loop
    }

    /// Stop all services and monitoring.
    func stop() {
        appState.isMonitoring = false
        // TODO: Plan 01-04 — stop FileWatcher, flush Logger
    }
}
