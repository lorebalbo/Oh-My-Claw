import SwiftUI

/// Menu bar dropdown with status, monitoring controls, and warnings.
struct MenuBarView: View {
    @Environment(AppCoordinator.self) private var coordinator

    /// Color for the status indicator dot.
    private var statusColor: Color {
        switch coordinator.appState.monitoringState {
        case .idle: return .green
        case .processing: return .blue
        case .paused: return .gray
        case .error: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(coordinator.appState.monitoringState.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(coordinator.appState.monitoringState == .paused ? "Resume Monitoring" : "Pause Monitoring") {
                Task {
                    if case .paused = coordinator.appState.monitoringState {
                        await coordinator.toggleMonitoring(true)
                    } else {
                        await coordinator.toggleMonitoring(false)
                    }
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
        .frame(width: 300)
        .task {
            await coordinator.start()
        }
    }
}
