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
                .onChange(of: coordinator.appState.isMonitoring) { _, newValue in
                    Task {
                        await coordinator.toggleMonitoring(newValue)
                    }
                }

            if !coordinator.appState.ffmpegAvailable {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("ffmpeg not found", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Install via: brew install ffmpeg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Audio files will be moved without conversion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !coordinator.appState.openaiApiKeyConfigured {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("OpenAI API key not configured", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Add your API key to config.json (pdf.openaiApiKey).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("PDF classification is paused until configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button("Quit Oh My Claw") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 220)
        .task {
            await coordinator.start()
        }
    }
}
