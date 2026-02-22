import AudioToolbox
import AVFoundation
import CoreMedia
import Foundation

/// Metadata extracted from an audio file.
struct AudioMetadata: Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let durationSeconds: Double
    let format: AudioFormat
    let bitrateKbps: Int

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

        let (format, bitrateKbps) = try await readFormatInfo(from: url, asset: asset)

        return AudioMetadata(
            title: title?.nonEmptyTrimmed,
            artist: artist?.nonEmptyTrimmed,
            album: album?.nonEmptyTrimmed,
            durationSeconds: seconds,
            format: format,
            bitrateKbps: bitrateKbps
        )
    }

    // MARK: - Format & Bitrate Extraction

    /// Extracts codec format and bitrate from the asset's audio track.
    ///
    /// Inspects `formatDescriptions` to resolve codec identity (critical for
    /// M4A containers which may hold either AAC or ALAC). Falls back to file
    /// extension when no audio track or format descriptions are available.
    /// Lossless formats force `bitrateKbps` to 0 (estimatedDataRate is
    /// unreliable for lossless).
    private func readFormatInfo(from url: URL, asset: AVURLAsset) async throws -> (AudioFormat, Int) {
        let tracks = try await asset.load(.tracks)
        guard let audioTrack = tracks.first(where: { $0.mediaType == .audio }) else {
            return (AudioFormat.fromExtension(url.pathExtension), 0)
        }

        let estimatedDataRate = try await audioTrack.load(.estimatedDataRate)
        let bitrateRaw = Int(estimatedDataRate / 1000)

        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        let format: AudioFormat

        if let firstDesc = formatDescriptions.first {
            let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(firstDesc)
            let formatID = audioDesc?.pointee.mFormatID ?? 0

            switch formatID {
            case kAudioFormatMPEGLayer3:
                format = .mp3
            case kAudioFormatMPEG4AAC:
                format = .aac
            case kAudioFormatAppleLossless:
                format = .alac
            case kAudioFormatLinearPCM:
                // Both WAV and AIFF use Linear PCM — distinguish by extension.
                format = url.pathExtension.lowercased() == "aiff"
                    || url.pathExtension.lowercased() == "aif"
                    ? .aiff : .wav
            case kAudioFormatFLAC:
                format = .flac
            default:
                format = AudioFormat.fromExtension(url.pathExtension)
            }
        } else {
            format = AudioFormat.fromExtension(url.pathExtension)
        }

        // Lossless: estimatedDataRate may be 0 or misleading — force to 0.
        let bitrateKbps = format.isLossless ? 0 : bitrateRaw
        return (format, bitrateKbps)
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
