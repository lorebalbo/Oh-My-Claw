import Foundation

/// Result of a config reload attempt.
enum ReloadResult: Sendable {
    /// Config file content is identical to current config — no action needed.
    case unchanged
    /// Config was valid and different — successfully updated.
    case updated
    /// Config was invalid — old config retained. Contains error descriptions.
    case invalid([String])
}

/// Loads, saves, and validates the JSON configuration file.
/// On first launch, copies bundled defaults to Application Support.
/// On invalid config, falls back to defaults and posts a notification.
@MainActor
@Observable
final class ConfigStore {
    private(set) var config: AppConfig
    private(set) var validationErrors: [String] = []

    private let configURL: URL
    private let backupURL: URL
    private let defaults: AppConfig

    /// Public read-only access to the config file path. Used by ConfigFileWatcher.
    var configFileURL: URL { configURL }

    /// Initialize with the standard config path.
    /// Pass a custom URL only for testing.
    init(configURL: URL? = nil) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("OhMyClaw", isDirectory: true)
        self.configURL = configURL ?? appSupport.appendingPathComponent("config.json")
        self.backupURL = self.configURL.deletingLastPathComponent().appendingPathComponent("config.last-good.json")
        self.defaults = AppConfig.defaults
        self.config = AppConfig.defaults
    }

    /// Load config from disk. Creates the file from bundled defaults on first launch.
    func load() {
        // Ensure the Application Support/OhMyClaw/ directory exists
        let directory = configURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // First launch: no config file exists yet
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            // Copy bundled defaults to Application Support
            if let bundledURL = Bundle.main.url(forResource: "default-config", withExtension: "json"),
               let bundledData = try? Data(contentsOf: bundledURL) {
                try? bundledData.write(to: configURL, options: .atomic)
            }
            // Write hardcoded defaults (in case bundle resource is missing)
            save(defaults)
            return
        }

        // Load and decode existing config
        do {
            let data = try Data(contentsOf: configURL)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            let errors = validate(decoded)
            if errors.isEmpty {
                config = decoded
                validationErrors = []
                saveLastKnownGood(decoded)
            } else {
                // Keep current config active on invalid values (don't reset to defaults)
                validationErrors = errors
                loadLastKnownGood()
            }
        } catch {
            // Corrupt or unparseable JSON — try last-known-good backup before falling back to defaults
            validationErrors = ["Failed to parse config.json: \(error.localizedDescription). Keeping current config."]
            loadLastKnownGood()
        }
    }

    /// Save current config to disk atomically.
    func save(_ config: AppConfig) {
        self.config = config
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    /// Reload config from disk. Called when the config file changes externally.
    ///
    /// Behavior:
    /// - If the file can't be read or parsed: returns `.invalid`, keeps current config (NOT defaults)
    /// - If parsed but fails validation: returns `.invalid`, keeps current config
    /// - If valid but identical to current: returns `.unchanged`
    /// - If valid and different: updates `self.config`, returns `.updated`
    ///
    /// This differs from `load()` which falls back to defaults on error.
    /// `reload()` preserves the last-known-good config on any error.
    func reload() -> ReloadResult {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .invalid(["Config file not found at \(configURL.path)"])
        }

        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            return .invalid(["Failed to read config file: \(error.localizedDescription)"])
        }

        let decoded: AppConfig
        do {
            decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            return .invalid(["Failed to parse config JSON: \(error.localizedDescription)"])
        }

        let errors = validate(decoded)
        if !errors.isEmpty {
            validationErrors = errors
            return .invalid(errors)
        }

        if decoded == config {
            return .unchanged
        }

        config = decoded
        validationErrors = []
        saveLastKnownGood(decoded)
        AppLogger.shared.info("Config reloaded successfully")
        return .updated
    }

    /// Validate config values. Returns list of human-readable error descriptions.
    /// Empty list means config is fully valid.
    func validate(_ config: AppConfig) -> [String] {
        var errors: [String] = []

        // Watcher validation
        if config.watcher.debounceSeconds < 1.0 || config.watcher.debounceSeconds > 30.0 {
            errors.append("watcher.debounceSeconds must be between 1.0 and 30.0 (got \(config.watcher.debounceSeconds))")
        }
        if config.watcher.stabilityCheckInterval < 0.1 || config.watcher.stabilityCheckInterval > 5.0 {
            errors.append("watcher.stabilityCheckInterval must be between 0.1 and 5.0 (got \(config.watcher.stabilityCheckInterval))")
        }

        // Audio validation
        if config.audio.minDurationSeconds < 0 {
            errors.append("audio.minDurationSeconds must be >= 0 (got \(config.audio.minDurationSeconds))")
        }

        // PDF validation — no port validation needed for OpenAI API
        // API key is optional (empty means PDF classification is disabled)

        // Logging validation
        let validLevels = ["debug", "info", "warn", "error"]
        if !validLevels.contains(config.logging.level.lowercased()) {
            errors.append("logging.level must be one of \(validLevels) (got '\(config.logging.level)')")
        }
        if config.logging.maxFileSizeMB < 1 || config.logging.maxFileSizeMB > 100 {
            errors.append("logging.maxFileSizeMB must be between 1 and 100 (got \(config.logging.maxFileSizeMB))")
        }
        if config.logging.maxRotatedFiles < 1 || config.logging.maxRotatedFiles > 20 {
            errors.append("logging.maxRotatedFiles must be between 1 and 20 (got \(config.logging.maxRotatedFiles))")
        }

        return errors
    }

    // MARK: - Last-Known-Good Config Persistence

    /// Save a validated config as the last-known-good backup.
    private func saveLastKnownGood(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: backupURL, options: .atomic)
    }

    /// Attempt to restore from the last-known-good backup.
    /// Called when config.json is corrupted or invalid at startup.
    private func loadLastKnownGood() {
        guard FileManager.default.fileExists(atPath: backupURL.path),
              let data = try? Data(contentsOf: backupURL),
              let decoded = try? JSONDecoder().decode(AppConfig.self, from: data),
              validate(decoded).isEmpty else {
            return
        }
        config = decoded
        AppLogger.shared.info("Restored last-known-good config from backup")
    }
}
