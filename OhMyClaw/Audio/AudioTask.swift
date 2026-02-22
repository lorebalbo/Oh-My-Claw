import Foundation

/// Full audio processing pipeline conforming to FileTask.
///
/// Pipeline steps:
/// 1. Read metadata (AVFoundation)
/// 2. Validate required metadata fields
/// 3. Check minimum duration
/// 4. Check duplicates via MusicLibraryIndex
/// 5. Evaluate quality via QualityEvaluator
/// 6a. AIFF source → move directly to ~/Music
/// 6b. High quality + non-AIFF + ffmpeg → convert to AIFF + move to ~/Music
/// 6c. High quality + non-AIFF + no ffmpeg → degraded mode, move original
/// 6d. Low quality → quarantine to ~/Music/low_quality + CSV log
struct AudioTask: FileTask, Sendable {
    let id = "audio"
    let displayName = "Audio Detection"
    let isEnabled: Bool

    private let identifier: AudioFileIdentifier
    private let metadataReader: AudioMetadataReader
    private let libraryIndex: MusicLibraryIndex
    private let config: AudioConfig
    private let ffmpegPath: URL?
    private let conversionPool: ConversionPool?
    private let qualityCutoff: QualityTier
    private let csvWriter: CSVWriter

    init(identifier: AudioFileIdentifier,
         metadataReader: AudioMetadataReader,
         libraryIndex: MusicLibraryIndex,
         config: AudioConfig,
         ffmpegPath: URL? = nil,
         conversionPool: ConversionPool? = nil,
         qualityCutoff: QualityTier = .mp3_320,
         csvWriter: CSVWriter = CSVWriter(fileURL: URL(fileURLWithPath:
            NSString(string: "~/Library/Application Support/OhMyClaw/low_quality_log.csv")
                .expandingTildeInPath))) {
        self.identifier = identifier
        self.metadataReader = metadataReader
        self.libraryIndex = libraryIndex
        self.config = config
        self.ffmpegPath = ffmpegPath
        self.conversionPool = conversionPool
        self.qualityCutoff = qualityCutoff
        self.csvWriter = csvWriter
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

        // Step 5: Evaluate quality (AUD-07)
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

        let tier = QualityEvaluator.resolveTier(format: metadata.format, bitrateKbps: metadata.bitrateKbps)
        let isHighQuality = QualityEvaluator.isHighQuality(tier: tier, cutoff: qualityCutoff)

        if isHighQuality {
            // Step 6a: AIFF source → move directly (no conversion needed)
            if metadata.format == .aiff {
                return try await moveHighQualityFile(file, to: musicDir, title: title, artist: artist,
                    action: "Moved AIFF to ~/Music (no conversion needed)")
            }

            // Step 6b: High quality + non-AIFF + ffmpeg available → convert + move
            if let ffmpegPath, let conversionPool {
                await conversionPool.acquire()

                let aiffFilename = file.deletingPathExtension().lastPathComponent + ".aiff"
                let destination = musicDir.appendingPathComponent(aiffFilename)

                do {
                    try await FFmpegConverter.convert(input: file, output: destination, ffmpegPath: ffmpegPath)
                    await conversionPool.release()
                } catch {
                    await conversionPool.release()
                    AppLogger.shared.error("Conversion failed", context: [
                        "file": file.lastPathComponent,
                        "error": "\(error)"
                    ])
                    return .error(description: "ffmpeg conversion failed: \(error)")
                }

                // Delete original from ~/Downloads
                try FileManager.default.removeItem(at: file)

                if let title, let artist {
                    await libraryIndex.add(title: title, artist: artist, url: destination)
                }

                AppLogger.shared.info("Converted to AIFF and moved to ~/Music", context: [
                    "file": file.lastPathComponent,
                    "title": title ?? "unknown",
                    "artist": artist ?? "unknown"
                ])
                return .processed(action: "Converted to AIFF and moved to ~/Music")
            }

            // Step 6c: High quality + non-AIFF + NO ffmpeg → degraded mode
            return try await moveHighQualityFile(file, to: musicDir, title: title, artist: artist,
                action: "Moved to ~/Music (ffmpeg unavailable, original format)",
                degraded: true)
        }

        // Step 6d: Low quality or unknown → quarantine
        let lowQualityDir = musicDir.appendingPathComponent("low_quality", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: lowQualityDir, withIntermediateDirectories: true)
        } catch {
            return .error(description: "Failed to create low_quality directory: \(error)")
        }

        let lowQualityDest = lowQualityDir.appendingPathComponent(file.lastPathComponent)
        if FileManager.default.fileExists(atPath: lowQualityDest.path) {
            AppLogger.shared.info("Low-quality duplicate skipped", context: [
                "file": file.lastPathComponent
            ])
        } else {
            do {
                try FileManager.default.moveItem(at: file, to: lowQualityDest)
            } catch {
                return .error(description: "Failed to move to low_quality: \(error)")
            }
        }

        // Log to CSV
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        let csvRow = CSVRow(
            filename: file.lastPathComponent,
            title: title ?? "",
            artist: artist ?? "",
            album: metadata.album ?? "",
            format: file.pathExtension,
            bitrate: "\(metadata.bitrateKbps)",
            date: today
        )
        try csvWriter.append(row: csvRow)

        // Delete original from ~/Downloads if it still exists (may have been moved already)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }

        AppLogger.shared.info("Quarantined to ~/Music/low_quality", context: [
            "file": file.lastPathComponent,
            "tier": tier?.rawValue ?? "unknown"
        ])
        return .processed(action: "Quarantined to ~/Music/low_quality")
    }

    // MARK: - Helpers

    /// Moves a high-quality file to the destination directory, updates library index, and returns the result.
    private func moveHighQualityFile(_ file: URL, to directory: URL,
                                     title: String?, artist: String?,
                                     action: String,
                                     degraded: Bool = false) async throws -> TaskResult {
        let finalDestination: URL
        do {
            finalDestination = try moveFile(file, to: directory)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            AppLogger.shared.error("Permission denied moving audio file", context: [
                "file": file.lastPathComponent,
                "destination": directory.path
            ])
            return .error(description: "Permission denied: \(error)")
        } catch {
            return .error(description: "Failed to move file: \(error)")
        }

        if let title, let artist {
            await libraryIndex.add(title: title, artist: artist, url: finalDestination)
        }

        if degraded {
            AppLogger.shared.warn("Degraded mode: moved without conversion", context: [
                "file": file.lastPathComponent
            ])
        } else {
            AppLogger.shared.info("Audio moved to ~/Music", context: [
                "file": file.lastPathComponent,
                "title": title ?? "unknown",
                "artist": artist ?? "unknown"
            ])
        }
        return .processed(action: action)
    }

    /// Moves a file to the destination directory with filename conflict handling.
    /// Returns the final destination URL.
    private func moveFile(_ file: URL, to directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent(file.lastPathComponent)
        var finalDestination = destination

        if FileManager.default.fileExists(atPath: destination.path) {
            let duplicateDir = directory.appendingPathComponent("possible_duplicate", isDirectory: true)
            try FileManager.default.createDirectory(at: duplicateDir, withIntermediateDirectories: true)
            finalDestination = duplicateDir.appendingPathComponent(file.lastPathComponent)

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

        return finalDestination
    }
}
