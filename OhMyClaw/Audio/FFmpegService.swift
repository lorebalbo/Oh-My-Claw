import Foundation

// MARK: - ConversionError

/// Errors produced during ffmpeg conversion.
enum ConversionError: Error, Sendable {
    /// ffmpeg exited with a non-zero status code.
    case ffmpegFailed(exitCode: Int32, stderr: String)
    /// The ffmpeg Process could not be launched.
    case processLaunchFailed(Error)
}

// MARK: - FFmpegLocator

/// Finds the ffmpeg binary on the local system.
///
/// Search order:
/// 1. `/opt/homebrew/bin/ffmpeg` (Apple Silicon Homebrew)
/// 2. `/usr/local/bin/ffmpeg` (Intel Homebrew)
/// 3. PATH lookup via `/usr/bin/which`
struct FFmpegLocator: Sendable {

    static func locate() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
        ]

        // Check known Homebrew paths first
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // Fallback: search PATH via /usr/bin/which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}

// MARK: - FFmpegConverter

/// Converts audio files to AIFF 16-bit using ffmpeg.
///
/// Writes output to a temp file in the system temporary directory
/// (UUID-prefixed to avoid race conditions), then atomically renames
/// to the final destination on success. Cleans up the temp file on
/// any failure path.
struct FFmpegConverter: Sendable {

    /// Converts `input` to AIFF 16-bit PCM, writing the result to `output`.
    ///
    /// - Parameters:
    ///   - input: Source audio file URL.
    ///   - output: Destination URL for the converted .aiff file.
    ///   - ffmpegPath: Path to the ffmpeg executable.
    static func convert(input: URL, output: URL, ffmpegPath: URL) async throws {
        let tempOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".aiff")

        let process = Process()
        process.executableURL = ffmpegPath
        process.arguments = [
            "-i", input.path,
            "-f", "aiff",
            "-acodec", "pcm_s16be",
            "-y",
            tempOutput.path,
        ]

        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { terminatedProcess in
                if terminatedProcess.terminationStatus == 0 {
                    // Atomic rename: remove existing output, move temp into place
                    do {
                        let fm = FileManager.default
                        if fm.fileExists(atPath: output.path) {
                            try fm.removeItem(at: output)
                        }
                        try fm.moveItem(at: tempOutput, to: output)
                        continuation.resume()
                    } catch {
                        try? FileManager.default.removeItem(at: tempOutput)
                        continuation.resume(throwing: error)
                    }
                } else {
                    // Read stderr after termination (safe — no pipe deadlock for audio-only conversion)
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
                    try? FileManager.default.removeItem(at: tempOutput)
                    continuation.resume(
                        throwing: ConversionError.ffmpegFailed(
                            exitCode: terminatedProcess.terminationStatus,
                            stderr: stderrString
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                try? FileManager.default.removeItem(at: tempOutput)
                continuation.resume(throwing: ConversionError.processLaunchFailed(error))
            }
        }
    }
}
