import Foundation

/// Loads, saves, and validates the JSON configuration file.
/// On first launch, copies bundled defaults to Application Support.
/// On invalid config, falls back to defaults and posts a notification.
@MainActor
@Observable
final class ConfigStore {
    private(set) var config: AppConfig
    private(set) var validationErrors: [String] = []

    private let configURL: URL
    private let defaults: AppConfig

    /// Initialize with the standard config path.
    /// Pass a custom URL only for testing.
    init(configURL: URL? = nil) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("OhMyClaw", isDirectory: true)
        self.configURL = configURL ?? appSupport.appendingPathComponent("config.json")
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
            } else {
                // Fallback to defaults for invalid values, notify user
                config = defaults
                validationErrors = errors
                // NotificationManager will be wired in Plan 01-04
                // For now, store errors in validationErrors for consumers to check
            }
        } catch {
            // Corrupt or unparseable JSON — use defaults entirely
            config = defaults
            validationErrors = ["Failed to parse config.json: \(error.localizedDescription). Using defaults."]
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

    /// Validate config values. Returns list of human-readable error descriptions.
    /// Empty list means config is fully valid.
    private func validate(_ config: AppConfig) -> [String] {
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
}
