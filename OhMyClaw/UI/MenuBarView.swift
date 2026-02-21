import SwiftUI

/// Minimal menu bar dropdown for Phase 1.
/// Contains only: monitoring toggle (switch-style) + Quit button.
struct MenuBarView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Monitoring", isOn: $coordinator.appState.isMonitoring)
                .toggleStyle(.switch)
                .tint(.green)

            Divider()

            Button("Quit Oh My Claw") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 220)
    }
}
