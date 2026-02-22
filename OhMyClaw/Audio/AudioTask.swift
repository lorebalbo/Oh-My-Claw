import Foundation

/// Full audio processing pipeline conforming to FileTask.
///
/// Pipeline steps:
/// 1. Read metadata (AVFoundation)
/// 2. Validate required metadata fields
/// 3. Check minimum duration
/// 4. Check duplicates via MusicLibraryIndex
/// 5. Move to ~/Music (with filename conflict handling)
struct AudioTask: FileTask, Sendable {
    let id = "audio"
    let displayName = "Audio Detection"
    let isEnabled: Bool

    private let identifier: AudioFileIdentifier
    private let metadataReader: AudioMetadataReader
    private let libraryIndex: MusicLibraryIndex
    private let config: AudioConfig

    init(identifier: AudioFileIdentifier,
         metadataReader: AudioMetadataReader,
         libraryIndex: MusicLibraryIndex,
         config: AudioConfig) {
        self.identifier = identifier
        self.metadataReader = metadataReader
        self.libraryIndex = libraryIndex
        self.config = config
        self.isEnabled = config.enabled
    }

    // MARK: - FileTask

    func canHandle(file: URL) -> Bool {
        identifier.isRecognizedAudioFile(file)
    }

    func process(file: URL) async throws -> TaskResult {
        // Step 1: Read metadata
        let metadata: AudioMetadata
        do {
            metadata = try await metadataReader.read(from: file)
        } catch {
            return .error(description: "Failed to read metadata: \(error)")
        }

        // Step 2: Validate required metadata fields (AUD-02)
        if !metadata.hasRequiredFields(config.requiredMetadataFields) {
            let missing = metadata.missingFields(config.requiredMetadataFields).joined(separator: ", ")
            AppLogger.shared.info("Audio skipped: missing metadata", context: [
                "file": file.lastPathComponent,
                "missing": missing
            ])
            return .skipped(reason: "Missing metadata: \(missing)")
        }

        // Step 3: Check minimum duration (AUD-03)
        if Int(metadata.durationSeconds) < config.minDurationSeconds {
            AppLogger.shared.info("Audio skipped: duration too short", context: [
                "file": file.lastPathComponent,
                "duration": "\(Int(metadata.durationSeconds))s",
                "minimum": "\(config.minDurationSeconds)s"
            ])
            return .skipped(reason: "Duration \(Int(metadata.durationSeconds))s < \(config.minDurationSeconds)s minimum")
        }

        // Step 4: Check duplicates (AUD-04 + AUD-05)
        let title = metadata.title
        let artist = metadata.artist

        if let title, let artist {
            if await libraryIndex.contains(title: title, artist: artist) {
                do {
                    try FileManager.default.removeItem(at: file)
                } catch {
                    AppLogger.shared.error("Failed to delete duplicate", context: [
                        "file": file.lastPathComponent,
                        "error": error.localizedDescription
                    ])
                    return .error(description: "Failed to delete duplicate: \(error)")
                }
                AppLogger.shared.info("Audio duplicate deleted", context: [
                    "file": file.lastPathComponent,
                    "title": title,
                    "artist": artist
                ])
                return .duplicate(title: title, artist: artist)
            }
        }

        // Step 5: Move to ~/Music (AUD-06)
        let destinationPath = NSString(string: config.destinationPath).expandingTildeInPath
        let musicDir = URL(fileURLWithPath: destinationPath, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.error("Failed to create destination directory", context: [
                "path": destinationPath,
                "error": error.localizedDescription
            ])
            return .error(description: "Failed to create destination: \(error)")
        }

        let destination = musicDir.appendingPathComponent(file.lastPathComponent)
        var finalDestination = destination

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                // Filename conflict — different content, same name
                let duplicateDir = musicDir.appendingPathComponent("possible_duplicate", isDirectory: true)
                try FileManager.default.createDirectory(at: duplicateDir, withIntermediateDirectories: true)
                finalDestination = duplicateDir.appendingPathComponent(file.lastPathComponent)

                // Handle conflict within possible_duplicate/ too
                if FileManager.default.fileExists(atPath: finalDestination.path) {
                    try FileManager.default.removeItem(at: finalDestination)
                }

                try FileManager.default.moveItem(at: file, to: finalDestination)
                AppLogger.shared.info("Filename conflict — moved to possible_duplicate", context: [
                    "file": file.lastPathComponent
                ])
            } else {
                try FileManager.default.moveItem(at: file, to: finalDestination)
            }
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            AppLogger.shared.error("Permission denied moving audio file", context: [
                "file": file.lastPathComponent,
                "destination": finalDestination.path
            ])
            return .error(description: "Permission denied: \(error)")
        } catch {
            return .error(description: "Failed to move file: \(error)")
        }

        // Update the library index
        if let title, let artist {
            await libraryIndex.add(title: title, artist: artist, url: finalDestination)
        }

        AppLogger.shared.info("Audio moved to ~/Music", context: [
            "file": file.lastPathComponent,
            "title": title ?? "unknown",
            "artist": artist ?? "unknown"
        ])
        return .processed(action: "Moved to ~/Music")
    }
}
