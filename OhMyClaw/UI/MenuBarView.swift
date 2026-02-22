import SwiftUI
import ServiceManagement

/// Menu bar dropdown with status, monitoring controls, settings, and app actions.
struct MenuBarView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var modelText: String = ""

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

    // MARK: - Settings Section

    @ViewBuilder
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Duration threshold — preset picker
            LabeledContent("Min Duration") {
                Picker("", selection: durationBinding) {
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                    Text("90s").tag(90)
                    Text("120s").tag(120)
                }
                .labelsHidden()
                .frame(width: 80)
            }

            // Quality cutoff — dropdown, highest to lowest
            LabeledContent("Quality Cutoff") {
                Picker("", selection: qualityCutoffBinding) {
                    ForEach(QualityTier.allCases.reversed(), id: \.self) { tier in
                        Text(tier.displayName).tag(tier.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }

            // OpenAI model — text field
            LabeledContent("OpenAI Model") {
                TextField("gpt-4o", text: modelBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit {
                        validateAndSaveModel()
                    }
            }
        }
    }

    // MARK: - Settings Bindings

    private var durationBinding: Binding<Int> {
        Binding(
            get: {
                coordinator.configStore?.config.audio.minDurationSeconds ?? 60
            },
            set: { newValue in
                guard var config = coordinator.configStore?.config else { return }
                config.audio.minDurationSeconds = newValue
                coordinator.configStore?.save(config)
            }
        )
    }

    private var qualityCutoffBinding: Binding<String> {
        Binding(
            get: {
                coordinator.configStore?.config.audio.qualityCutoff ?? "mp3_320"
            },
            set: { newValue in
                guard var config = coordinator.configStore?.config else { return }
                config.audio.qualityCutoff = newValue
                coordinator.configStore?.save(config)
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: {
                if modelText.isEmpty {
                    return coordinator.configStore?.config.pdf.openaiModel ?? "gpt-4o"
                }
                return modelText
            },
            set: { newValue in
                modelText = newValue
            }
        )
    }

    private func validateAndSaveModel() {
        let trimmed = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Reset to current config value
            modelText = ""
            return
        }
        guard var config = coordinator.configStore?.config else { return }
        config.pdf.openaiModel = trimmed
        coordinator.configStore?.save(config)
        modelText = ""
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
