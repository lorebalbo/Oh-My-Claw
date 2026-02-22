import SwiftUI

@main
struct OhMyClawApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(coordinator)
        } label: {
            switch coordinator.appState.monitoringState {
            case .paused:
                Image(systemName: coordinator.appState.menuBarIcon)
                    .symbolRenderingMode(.hierarchical)
            case .processing:
                Image(systemName: coordinator.iconAnimator.currentIconName)
            case .error:
                Image(systemName: coordinator.appState.menuBarIcon)
            case .idle:
                Image(systemName: coordinator.appState.menuBarIcon)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
