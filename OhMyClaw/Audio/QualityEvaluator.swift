import Foundation

// MARK: - AudioFormat

/// Identifies the codec/container format of an audio file.
enum AudioFormat: Sendable, Equatable {
    case mp3
    case aac
    case alac
    case flac
    case wav
    case aiff
    case unknown(extension: String)

    /// Whether this format is lossless (no audio data lost during encoding).
    var isLossless: Bool {
        switch self {
        case .wav, .flac, .alac, .aiff:
            return true
        case .mp3, .aac, .unknown:
            return false
        }
    }

    /// Maps a file extension to an `AudioFormat`.
    ///
    /// - Note: `.m4a` defaults to `.aac`; callers should override with
    ///   `formatDescriptions` inspection to detect ALAC-in-M4A.
    static func fromExtension(_ ext: String) -> AudioFormat {
        switch ext.lowercased() {
        case "mp3":
            return .mp3
        case "m4a", "aac":
            return .aac
        case "flac":
            return .flac
        case "wav":
            return .wav
        case "aiff", "aif":
            return .aiff
        default:
            return .unknown(extension: ext.lowercased())
        }
    }
}

// MARK: - QualityTier

/// Ranked quality tiers from lowest to highest.
///
/// Raw values match `AppConfig.qualityCutoff` keys (e.g. `"mp3_320"`).
/// Comparable conformance uses case order: lower index → lower quality.
enum QualityTier: String, Comparable, CaseIterable, Codable, Sendable {
    case mp3_128
    case aac_256
    case mp3_320
    case aiff
    case alac
    case flac
    case wav

    // MARK: Comparable

    static func < (lhs: QualityTier, rhs: QualityTier) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    private var ordinal: Int {
        // Force-unwrap is safe: every case is guaranteed to appear in allCases.
        Self.allCases.firstIndex(of: self)!
    }
}

// MARK: - QualityEvaluator

/// Resolves an `AudioFormat` + bitrate into a `QualityTier` and compares
/// against a configurable cutoff.
struct QualityEvaluator: Sendable {

    /// Maps a format and bitrate to the highest matching tier.
    ///
    /// - Lossless formats bypass the bitrate check entirely.
    /// - Lossy formats round **down** to the nearest tier entry (conservative).
    /// - Unknown formats always return `nil`.
    static func resolveTier(format: AudioFormat, bitrateKbps: Int) -> QualityTier? {
        switch format {
        case .wav:
            return .wav
        case .flac:
            return .flac
        case .alac:
            return .alac
        case .aiff:
            return .aiff
        case .mp3:
            if bitrateKbps >= 320 { return .mp3_320 }
            if bitrateKbps >= 128 { return .mp3_128 }
            return nil
        case .aac:
            if bitrateKbps >= 256 { return .aac_256 }
            return nil
        case .unknown:
            return nil
        }
    }

    /// Returns `true` when `tier` is at or above `cutoff` (inclusive).
    static func isHighQuality(tier: QualityTier?, cutoff: QualityTier) -> Bool {
        guard let tier else { return false }
        return tier >= cutoff
    }
}

// MARK: - QualityTier Display Names

extension QualityTier {
    /// Human-readable name for UI display in quality cutoff picker.
    var displayName: String {
        switch self {
        case .wav: return "WAV"
        case .flac: return "FLAC"
        case .alac: return "ALAC"
        case .aiff: return "AIFF"
        case .mp3_320: return "MP3 320"
        case .aac_256: return "AAC 256"
        case .mp3_128: return "MP3 128"
        }
    }
}
