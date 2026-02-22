import Foundation

/// Top-level configuration model. Nested by feature area.
/// Uses Codable with default values so that missing keys in the user's JSON
/// fall back to hardcoded defaults rather than failing to decode.
struct AppConfig: Codable, Equatable, Sendable {
    var watcher: WatcherConfig
    var audio: AudioConfig
    var pdf: PDFConfig
    var logging: LoggingConfig

    /// Hardcoded defaults — the single source of truth for default values.
    static let defaults = AppConfig(
        watcher: .defaults,
        audio: .defaults,
        pdf: .defaults,
        logging: .defaults
    )

    enum CodingKeys: String, CodingKey {
        case watcher, audio, pdf, logging
    }

    init(watcher: WatcherConfig, audio: AudioConfig, pdf: PDFConfig, logging: LoggingConfig) {
        self.watcher = watcher
        self.audio = audio
        self.pdf = pdf
        self.logging = logging
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        watcher = (try? container.decode(WatcherConfig.self, forKey: .watcher)) ?? .defaults
        audio = (try? container.decode(AudioConfig.self, forKey: .audio)) ?? .defaults
        pdf = (try? container.decode(PDFConfig.self, forKey: .pdf)) ?? .defaults
        logging = (try? container.decode(LoggingConfig.self, forKey: .logging)) ?? .defaults
    }
}

struct WatcherConfig: Codable, Equatable, Sendable {
    var debounceSeconds: Double
    var stabilityCheckInterval: Double
    var ignoredExtensions: [String]

    static let defaults = WatcherConfig(
        debounceSeconds: 3.0,
        stabilityCheckInterval: 0.5,
        ignoredExtensions: [".crdownload", ".part", ".tmp", ".download", ".partial", ".downloading"]
    )
}

struct AudioConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var requiredMetadataFields: [String]
    var minDurationSeconds: Int
    var qualityCutoff: String
    var destinationPath: String

    static let defaults = AudioConfig(
        enabled: true,
        requiredMetadataFields: ["title", "artist", "album"],
        minDurationSeconds: 60,
        qualityCutoff: "mp3_320",
        destinationPath: "~/Music"
    )
}

struct PDFConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var openaiApiKey: String
    var openaiModel: String
    var destinationPath: String

    static let defaults = PDFConfig(
        enabled: true,
        openaiApiKey: "",
        openaiModel: "gpt-4o",
        destinationPath: "~/Documents/Papers"
    )

    enum CodingKeys: String, CodingKey {
        case enabled, openaiApiKey, openaiModel, destinationPath
    }

    init(enabled: Bool, openaiApiKey: String, openaiModel: String, destinationPath: String) {
        self.enabled = enabled
        self.openaiApiKey = openaiApiKey
        self.openaiModel = openaiModel
        self.destinationPath = destinationPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? Self.defaults.enabled
        openaiApiKey = (try? container.decode(String.self, forKey: .openaiApiKey)) ?? Self.defaults.openaiApiKey
        openaiModel = (try? container.decode(String.self, forKey: .openaiModel)) ?? Self.defaults.openaiModel
        destinationPath = (try? container.decode(String.self, forKey: .destinationPath)) ?? Self.defaults.destinationPath
    }
}

struct LoggingConfig: Codable, Equatable, Sendable {
    var level: String
    var maxFileSizeMB: Int
    var maxRotatedFiles: Int

    static let defaults = LoggingConfig(
        level: "info",
        maxFileSizeMB: 10,
        maxRotatedFiles: 3
    )
}
