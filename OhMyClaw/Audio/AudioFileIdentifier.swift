import Foundation
import UniformTypeIdentifiers

/// Identifies whether a file URL points to a recognized audio file.
///
/// Uses a dual-gate approach: the file extension must be in the known set
/// AND the UTType for that extension must conform to `.audio`.
struct AudioFileIdentifier: Sendable {
    /// Extensions recognized by the audio pipeline.
    /// Covers MP3, AAC/M4A (also ALAC in .m4a container), FLAC, WAV, and AIFF.
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif"
    ]

    /// Returns `true` only if the file has a known audio extension
    /// AND the system's UTType for that extension conforms to `.audio`.
    func isRecognizedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()

        guard Self.supportedExtensions.contains(ext) else {
            return false
        }

        guard let utType = UTType(filenameExtension: ext),
              utType.conforms(to: .audio) else {
            return false
        }

        return true
    }
}
