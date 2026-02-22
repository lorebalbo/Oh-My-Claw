import SwiftUI
import ServiceManagement

/// Menu bar dropdown with status, monitoring controls, settings, and app actions.
struct MenuBarView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // — Status —
            statusSection

            Divider()

            // — Monitoring —
            monitoringSection

            Divider()

            // — Settings (placeholder for 05-03) —
            settingsSection

            Divider()

            // — App —
            appSection
        }
        .padding(16)
        .frame(width: 300)
        .task {
            await coordinator.start()
        }
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(coordinator.appState.monitoringState.statusText)
                .font(.headline)
        }
    }

    private var statusColor: Color {
        switch coordinator.appState.monitoringState {
        case .idle: return .green
        case .processing: return .blue
        case .paused: return .gray
        case .error: return .red
        }
    }

    // MARK: - Monitoring Section

    @ViewBuilder
    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monitoring")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Button(pauseResumeLabel) {
                Task {
                    if case .paused = coordinator.appState.monitoringState {
                        await coordinator.resumeMonitoring()
                    } else {
                        coordinator.pauseMonitoring()
                    }
                }
            }

            if !coordinator.appState.ffmpegAvailable {
                VStack(alignment: .leading, spacing: 4) {
                    Label("ffmpeg not found", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Install via: brew install ffmpeg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Audio files will be moved without conversion.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !coordinator.appState.openaiApiKeyConfigured {
                VStack(alignment: .leading, spacing: 4) {
                    Label("OpenAI API key not configured", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Add your API key to config.json (pdf.openaiApiKey).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("PDF classification is paused until configured.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var pauseResumeLabel: String {
        if case .paused = coordinator.appState.monitoringState {
            return "Resume Monitoring"
        }
        return "Pause Monitoring"
    }

    // MARK: - Settings Section (placeholder)

    @ViewBuilder
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("No configurable settings yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - App Section

    @ViewBuilder
    private var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle("Launch at Login", isOn: launchAtLoginBinding)
                .toggleStyle(.switch)

            Button("Quit Oh My Claw") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                SMAppService.mainApp.status == .enabled
            },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    AppLogger.shared.error("Launch at Login toggle failed",
                        context: ["action": newValue ? "register" : "unregister",
                                  "error": error.localizedDescription])
                }
            }
        )
    }
}
