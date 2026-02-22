import AVFoundation
import CoreMedia
import Foundation

/// Metadata extracted from an audio file.
struct AudioMetadata: Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let durationSeconds: Double

    /// Returns `true` only if ALL specified fields have non-nil values.
    ///
    /// Valid field names: `"title"`, `"artist"`, `"album"`.
    /// Unrecognized field names are treated as missing (returns `false`).
    func hasRequiredFields(_ fields: [String]) -> Bool {
        missingFields(fields).isEmpty
    }

    /// Returns the names of fields that are nil among the specified list.
    func missingFields(_ fields: [String]) -> [String] {
        fields.filter { field in
            switch field {
            case "title": return title == nil
            case "artist": return artist == nil
            case "album": return album == nil
            default: return true
            }
        }
    }
}

/// Reads metadata and duration from an audio file using AVFoundation's async API.
struct AudioMetadataReader: Sendable {
    /// Reads title, artist, album, and duration from the audio file at `url`.
    ///
    /// Uses `AVURLAsset.load(.duration, .metadata)` — the modern async API
    /// introduced in macOS 12. Never touches deprecated synchronous properties.
    func read(from url: URL) async throws -> AudioMetadata {
        let asset = AVURLAsset(url: url)

        let (duration, metadataItems) = try await asset.load(.duration, .metadata)
        let seconds = CMTimeGetSeconds(duration)

        let titleItem = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierTitle
        ).first

        let artistItem = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierArtist
        ).first

        let albumItem = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierAlbumName
        ).first

        let title = try? await titleItem?.load(.stringValue)
        let artist = try? await artistItem?.load(.stringValue)
        let album = try? await albumItem?.load(.stringValue)

        return AudioMetadata(
            title: title?.nonEmptyTrimmed,
            artist: artist?.nonEmptyTrimmed,
            album: album?.nonEmptyTrimmed,
            durationSeconds: seconds
        )
    }
}

// MARK: - String Extension

extension String {
    /// Trims whitespace and newlines; returns `nil` if the result is empty.
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
