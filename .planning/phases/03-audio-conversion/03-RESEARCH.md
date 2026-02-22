# Phase 3: Audio Conversion & Quality - Research

**Researched:** 2026-02-22
**Domain:** ffmpeg integration, audio quality evaluation, Swift concurrency, CSV logging
**Confidence:** HIGH

## Summary

Phase 3 extends the Phase 2 audio pipeline (detect → validate → deduplicate → move) by inserting quality evaluation and conditional conversion before the final move. The core technical domains are: (1) detecting ffmpeg at known Homebrew paths with fallback to PATH, (2) running ffmpeg as a child process via Swift's `Process` class with async wrappers, (3) evaluating audio quality using AVFoundation's `estimatedDataRate` and format descriptions from `AVAssetTrack`, (4) bounding parallel conversions with a Swift actor using a semaphore-like pattern, and (5) appending quarantine metadata to a CSV file.

The existing `AudioMetadata` struct needs two new fields: `format` (derived from file extension) and `bitrateKbps` (from `AVAssetTrack.estimatedDataRate`). The existing `AudioTask.process()` pipeline inserts quality evaluation between the duplicate check (step 4) and the move (step 5). Files at or above the cutoff get converted via ffmpeg to AIFF 16-bit; files below get moved to `~/Music/low_quality` and logged to CSV.

**Primary recommendation:** Use Swift `actor` for both the ffmpeg path checker and the conversion pool. Keep the quality ranking as a simple ordered enum with `Comparable` conformance. Write ffmpeg output to `.aiff.tmp` temp files and atomically rename on success.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Quality Evaluation Logic:**
- Bitrate mapping: Lossy formats (MP3, AAC) with bitrates between ranking entries round DOWN to the nearest entry (conservative — if not provably high-quality, treat as lower tier)
- Cutoff semantics: Files at or above the cutoff qualify as high quality (inclusive — `qualityCutoff: "mp3_320"` means MP3 320 qualifies for conversion)
- Unknown formats: Audio formats not in the ranking list (OGG, WMA, Opus, etc.) are treated as low quality and quarantined
- Lossless equivalence: All lossless formats (WAV, FLAC, ALAC, AIFF) are treated equally regardless of bit depth or sample rate — lossless is lossless
- VBR handling: Use average bitrate (as reported by AVFoundation) for ranking evaluation
- AAC threshold: AAC ≥ 256kbps all rank equal to AAC 256 in the ranking
- AIFF source files: Already in target format — skip conversion entirely, just move to ~/Music
- WAV source files: Convert to AIFF 16-bit for ~/Music format consistency (even though WAV ranks highest)

**Conversion Lifecycle:**
- Original file cleanup: Delete original from ~/Downloads after successful conversion + move to ~/Music
- Conversion failure: Leave original file untouched in ~/Downloads, log the error
- Partial output protection: Write ffmpeg output to a temp file (.aiff.tmp), atomic rename on success, delete temp on failure — never leave corrupt .aiff files in ~/Music
- Pipeline order: Duplicate check runs BEFORE conversion to avoid wasting CPU on files that will be deleted anyway

**Low-Quality Quarantine & CSV:**
- CSV location: ~/Library/Application Support/OhMyClaw/low_quality_log.csv (with other app data)
- CSV mode: Append (running log that grows over time, not reset per session)
- CSV columns: Filename, Title, Artist, Album, Format, Bitrate, Date
- Original cleanup: Delete original from ~/Downloads after moving to ~/Music/low_quality (same as high-quality path)
- Duplicate handling in low_quality: If same filename already exists in ~/Music/low_quality, skip the move (don't overwrite, don't suffix)

**ffmpeg Availability:**
- Install guidance: Persistent message in menu bar dropdown when ffmpeg is not found (visible until resolved)
- Degraded mode: Without ffmpeg, the audio pipeline still runs (detect, validate metadata, deduplicate, move to ~/Music) but skips the conversion step — files arrive in their original format
- Check frequency: Check at launch only; if ffmpeg disappears mid-session, conversion failures are logged as errors
- Path resolution: Search known Homebrew paths first (/usr/local/bin/ffmpeg for Intel, /opt/homebrew/bin/ffmpeg for Apple Silicon), then fall back to PATH lookup

### Claude's Discretion
- ffmpeg process arguments and encoding parameters for 16-bit AIFF output
- ConversionPool actor implementation details for CPU-core-bounded parallelism
- CSV formatting specifics (quoting, escaping, date format)
- Error message wording for ffmpeg install guidance
- Temp file naming convention and location

### Deferred Ideas (OUT OF SCOPE)
No deferred ideas — all discussion stayed within phase scope.

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUD-07 | Audio format quality is evaluated against configurable ranking (WAV > FLAC > ALAC > AIFF > MP3 320 > AAC 256 > MP3 128) | Quality ranking enum with `Comparable`, `AudioMetadata` extended with format+bitrate, `estimatedDataRate` from AVAssetTrack |
| AUD-08 | Files at or above the ranking cutoff are converted to AIFF 16-bit via ffmpeg | ffmpeg command: `ffmpeg -i input -f aiff -acodec pcm_s16be -y output.aiff.tmp`, Process wrapper, atomic rename |
| AUD-09 | Conversions run in parallel matching CPU core count | ConversionPool actor with semaphore pattern, `ProcessInfo.processInfo.processorCount` |
| AUD-10 | Files below the ranking cutoff or not in the ranking are moved to ~/Music/low_quality | Quality evaluation branching in AudioTask, FileManager move with duplicate skip |
| AUD-11 | Low-quality file metadata is logged to CSV (Filename, Title, Artist, Album, Format, Bitrate, Date) | CSV writer with append mode, proper quoting/escaping, ISO 8601 date |
| INF-01 | App checks for ffmpeg availability at launch and guides user to install if missing | FFmpegLocator with ordered path search, AppCoordinator integration, MenuBarView persistent message |

</phase_requirements>

## Standard Stack

### Core

| Component | Source | Purpose | Why Standard |
|-----------|--------|---------|--------------|
| `Process` (Foundation) | macOS SDK | Run ffmpeg as child process | Standard Swift API for launching external processes; supports stdin/stdout/stderr pipes, termination handlers |
| `AVAssetTrack.estimatedDataRate` | AVFoundation | Read audio bitrate | Already using AVFoundation for metadata; `estimatedDataRate` returns bits/sec as Float, works for both CBR and average VBR |
| `AVAssetTrack.formatDescriptions` | AVFoundation | Detect lossless vs lossy codec | `CMAudioFormatDescriptionGetStreamBasicDescription` exposes `mFormatID` (e.g., `kAudioFormatLinearPCM`, `kAudioFormatMPEGLayer3`) |
| Swift `actor` | Swift concurrency | Thread-safe ConversionPool with bounded concurrency | Project already uses actors (MusicLibraryIndex); natural fit for conversion pool |
| `ProcessInfo.processorCount` | Foundation | CPU core count for conversion cap | Returns logical CPU count (12 on test machine); matches AUD-09 requirement |

### Supporting

| Component | Source | Purpose | When to Use |
|-----------|--------|---------|-------------|
| `FileHandle` | Foundation | CSV append writes | `FileHandle(forWritingTo:)` with `seekToEndOfFile()` + `write()` for append mode |
| `Pipe` | Foundation | Capture ffmpeg stdout/stderr | Attached to `Process.standardOutput` / `standardError` to read conversion output and errors |
| `DispatchSemaphore` or async semaphore pattern | Foundation / Swift concurrency | Bound concurrent conversions | Actor-internal counter + continuations to limit in-flight ffmpeg processes |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Process` for ffmpeg | `NSTask` (deprecated name) | Same class — `Process` is the modern name since Swift 3 |
| Manual CSV formatting | TabularData framework | TabularData (macOS 12+) is for reading/analyzing CSVs, overkill for simple append-only writing |
| Actor semaphore | `OperationQueue.maxConcurrentOperationCount` | OperationQueue works but doesn't integrate with Swift concurrency; actor pattern matches existing codebase |
| File extension for format | UTType inference | Extension is simpler and sufficient given the known set of supported formats |

## Architecture Patterns

### Modified Audio Pipeline

Current pipeline (Phase 2):
```
detect → validate metadata → check duration → deduplicate → move to ~/Music
```

New pipeline (Phase 3):
```
detect → validate metadata → check duration → deduplicate → evaluate quality
  ├─ HIGH quality + AIFF source → move directly to ~/Music (skip conversion)
  ├─ HIGH quality + non-AIFF → convert via ffmpeg → move .aiff to ~/Music → delete original
  └─ LOW quality / unknown → move to ~/Music/low_quality → log to CSV → delete original
```

### Pattern 1: Quality Ranking Enum

**What:** Ordered enum representing audio quality tiers, with `Comparable` conformance.
**When to use:** Quality evaluation step — map file format+bitrate to a tier, compare against cutoff.

```swift
/// Ordered from lowest to highest quality.
/// RawValue matches config key (e.g., "mp3_128", "mp3_320").
enum QualityTier: String, Comparable, CaseIterable, Codable, Sendable {
    case mp3_128
    case aac_256
    case mp3_320
    case aiff
    case alac
    case flac
    case wav

    // Comparable via allCases index — lower index = lower quality
    private var ordinal: Int {
        Self.allCases.firstIndex(of: self)!
    }

    static func < (lhs: QualityTier, rhs: QualityTier) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}
```

**Key design decisions for tier resolution:**
- Lossless formats (WAV, FLAC, ALAC, AIFF) → their respective tier directly (no bitrate check)
- MP3: bitrate ≥ 320 → `.mp3_320`, bitrate ≥ 128 → `.mp3_128`, else → `nil` (unknown/low)
- AAC (m4a): bitrate ≥ 256 → `.aac_256`, else → `nil`
- Rounding DOWN for in-between bitrates (conservative, per user decision)
- Unknown formats → `nil` → treated as low quality

### Pattern 2: FFmpegLocator (Availability Check)

**What:** Struct that finds the ffmpeg binary path at launch.
**When to use:** AppCoordinator.start() — checked once, result stored.

```swift
struct FFmpegLocator: Sendable {
    /// Search order: Apple Silicon Homebrew → Intel Homebrew → PATH
    static func locate() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",     // Apple Silicon
            "/usr/local/bin/ffmpeg",        // Intel
        ]

        // Check known paths first
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: path) {
                return url
            }
        }

        // Fallback: search PATH via /usr/bin/which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // suppress stderr
        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
```

### Pattern 3: Async Process Wrapper

**What:** Run ffmpeg conversion as an async operation that returns a Result.
**When to use:** Each file conversion in the ConversionPool.

```swift
/// Run ffmpeg to convert an audio file to AIFF 16-bit.
/// Output goes to a .tmp file; caller handles atomic rename.
func convert(input: URL, output: URL, ffmpegPath: URL) async throws {
    let tempOutput = output.appendingPathExtension("tmp") // song.aiff.tmp

    let process = Process()
    process.executableURL = ffmpegPath
    process.arguments = [
        "-i", input.path,
        "-f", "aiff",
        "-acodec", "pcm_s16be",
        "-y",               // overwrite temp if exists
        tempOutput.path
    ]
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    return try await withCheckedThrowingContinuation { continuation in
        process.terminationHandler = { proc in
            if proc.terminationStatus == 0 {
                // Atomic rename: .aiff.tmp → .aiff
                do {
                    if FileManager.default.fileExists(atPath: output.path) {
                        try FileManager.default.removeItem(at: output)
                    }
                    try FileManager.default.moveItem(at: tempOutput, to: output)
                    continuation.resume()
                } catch {
                    try? FileManager.default.removeItem(at: tempOutput)
                    continuation.resume(throwing: error)
                }
            } else {
                // Clean up failed temp file
                try? FileManager.default.removeItem(at: tempOutput)
                let stderrData = (proc.standardError as? Pipe)?
                    .fileHandleForReading.readDataToEndOfFile() ?? Data()
                let stderr = String(data: stderrData, encoding: .utf8) ?? "unknown error"
                continuation.resume(throwing: ConversionError.ffmpegFailed(
                    exitCode: proc.terminationStatus, stderr: stderr))
            }
        }

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: tempOutput)
            continuation.resume(throwing: error)
        }
    }
}
```

### Pattern 4: ConversionPool Actor (Bounded Concurrency)

**What:** Actor that limits concurrent ffmpeg processes to CPU core count.
**When to use:** Called by AudioTask for each qualifying file needing conversion.

```swift
actor ConversionPool {
    private let maxConcurrent: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int = ProcessInfo.processInfo.processorCount) {
        self.maxConcurrent = maxConcurrent
    }

    /// Acquire a slot. Suspends if pool is full.
    func acquire() async {
        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        inFlight += 1
    }

    /// Release a slot. Resumes a waiter if any.
    func release() {
        inFlight -= 1
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}
```

Usage in AudioTask:
```swift
await conversionPool.acquire()
defer { Task { await conversionPool.release() } }
try await convert(input: file, output: destination, ffmpegPath: ffmpegURL)
```

> **Note on `defer` + actor:** The `defer` block uses `Task` to call back into the actor. This is necessary because `defer` blocks are synchronous. An alternative is a structured `do/catch` with explicit `release()` calls in both paths.

### Pattern 5: CSV Append Writer

**What:** Simple CSV writer that appends rows to a file, creating it with headers on first write.
**When to use:** After moving a low-quality file to ~/Music/low_quality.

```swift
struct CSVWriter: Sendable {
    let fileURL: URL
    private static let headers = "Filename,Title,Artist,Album,Format,Bitrate,Date"

    func append(row: CSVRow) throws {
        let fm = FileManager.default

        // Create file with headers if it doesn't exist
        if !fm.fileExists(atPath: fileURL.path) {
            let directory = fileURL.deletingLastPathComponent()
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try (Self.headers + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Append the row
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        let line = row.csvLine + "\n"
        handle.write(line.data(using: .utf8)!)
    }
}

struct CSVRow {
    let filename: String
    let title: String
    let artist: String
    let album: String
    let format: String
    let bitrate: String
    let date: String

    var csvLine: String {
        [filename, title, artist, album, format, bitrate, date]
            .map { escapeCSV($0) }
            .joined(separator: ",")
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
```

### Anti-Patterns to Avoid

- **Don't use `Process.waitUntilExit()` on the main thread or inside actors:** It blocks the thread. Always use `terminationHandler` with continuations or run on a background thread.
- **Don't read stderr before process exits:** The pipe buffer can fill up and deadlock. Read after termination or use separate reading tasks.
- **Don't skip the temp file pattern:** Writing directly to the final destination risks leaving corrupt `.aiff` files if the process crashes or is killed.
- **Don't use `OperationQueue` for conversion concurrency:** It doesn't compose well with Swift structured concurrency. Use an actor-based semaphore or `TaskGroup` with bounded iteration (pattern already established in `MusicLibraryIndex.build`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Audio format detection | Custom file header parsing | AVFoundation `AVAssetTrack.formatDescriptions` + file extension | AVFoundation handles container format detection reliably; extension is sufficient for the known supported set |
| Bitrate reading | Manual ffprobe parsing | `AVAssetTrack.estimatedDataRate` | Returns bits/sec as Float; handles CBR and VBR average; already using AVFoundation |
| AIFF conversion | Custom PCM encoding | ffmpeg CLI | ffmpeg handles all input formats, sample rate conversion, bit depth conversion in one command |
| CSV escaping | Regex-based escaping | RFC 4180 double-quote escaping (`"` → `""`, wrap in quotes if contains `,`/`"`) | Simple enough to implement correctly with 3 rules; no library needed |
| Process async wrapping | Custom run loops | `Process.terminationHandler` + `withCheckedThrowingContinuation` | Standard Swift concurrency bridge pattern |

**Key insight:** The audio conversion itself is entirely delegated to ffmpeg. The Swift code only needs to: (1) decide whether to convert, (2) launch ffmpeg with the right args, (3) handle success/failure. Don't try to do audio encoding in Swift.

## Common Pitfalls

### Pitfall 1: Process.terminationHandler Thread Safety
**What goes wrong:** `terminationHandler` runs on an arbitrary thread. Accessing actor-isolated state from within it causes data races.
**Why it happens:** `Process` is a Foundation class, not concurrency-aware.
**How to avoid:** Use `withCheckedThrowingContinuation` — the continuation resumes back on the caller's executor. Never mutate shared state directly inside `terminationHandler`.
**Warning signs:** Random crashes, TSan warnings.

### Pitfall 2: Pipe Buffer Deadlock
**What goes wrong:** ffmpeg writes a lot to stderr (progress, codec info). If the pipe buffer fills (64KB default on macOS), ffmpeg blocks waiting for the reader, and the Swift code blocks waiting for termination — deadlock.
**Why it happens:** Not reading from the pipe while the process is running.
**How to avoid:** Either (a) don't capture stderr (use `FileHandle.nullDevice`) if you don't need it, or (b) read stderr asynchronously on a separate task/thread, or (c) read `readDataToEndOfFile()` AFTER the process terminates (safe because ffmpeg outputs are typically small for audio-only conversions, well under 64KB).
**Warning signs:** Conversion hangs indefinitely on large files.
**Recommendation for this project:** Read stderr after termination. ffmpeg stderr for audio-only conversion is typically a few hundred bytes (format info + progress line). Unlikely to exceed 64KB buffer unless processing thousands of streams.

### Pitfall 3: estimatedDataRate Returns 0 for Some Lossless Files
**What goes wrong:** `AVAssetTrack.estimatedDataRate` may return 0 for certain lossless formats (especially FLAC, WAV) because the "data rate" concept doesn't apply the same way.
**Why it happens:** Lossless codecs have variable instantaneous rates; AVFoundation may not compute an estimate.
**How to avoid:** For lossless formats (identified by extension: wav, flac, aiff, m4a+ALAC), bypass bitrate evaluation entirely — they're always high quality per user decision "lossless is lossless." Only use `estimatedDataRate` for lossy formats (mp3, aac/m4a-lossy).
**Warning signs:** Lossless files incorrectly quarantined as low quality.

### Pitfall 4: M4A Container Ambiguity (AAC vs ALAC)
**What goes wrong:** `.m4a` files can contain either AAC (lossy) or ALAC (lossless). Treating all `.m4a` as AAC misclassifies ALAC files.
**Why it happens:** `.m4a` is a container format, not a codec.
**How to avoid:** Use `CMAudioFormatDescriptionGetStreamBasicDescription` to read `mFormatID`. ALAC = `kAudioFormatAppleLossless` (0x616C6163 = 'alac'). AAC = `kAudioFormatMPEG4AAC` (0x61616320 = 'aac ').
**Warning signs:** High-quality ALAC files quarantined as low-quality AAC.

### Pitfall 5: File Extension After Conversion
**What goes wrong:** The converted file keeps the original filename but needs `.aiff` extension.
**Why it happens:** Not changing the extension during the move.
**How to avoid:** When building the destination filename for converted files, replace the original extension with `.aiff`. E.g., `"song.mp3"` → `"song.aiff"`.
**Warning signs:** Files in ~/Music with wrong extensions that confuse media players.

### Pitfall 6: Race Condition on Temp File
**What goes wrong:** Two conversions of files with the same name (but different source directories or re-download) write to the same `.aiff.tmp` path.
**Why it happens:** Temp file named only from the output filename.
**How to avoid:** Include a UUID or use a unique temp directory per conversion. Or write to the system temp directory (`FileManager.default.temporaryDirectory`) with a UUID-prefixed name.
**Warning signs:** Corrupt output files, mysterious conversion failures.

## Code Examples

### Reading Bitrate and Format from AVFoundation

```swift
import AVFoundation
import CoreMedia

/// Extended metadata including format and bitrate for quality evaluation.
struct AudioMetadata: Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let durationSeconds: Double
    let format: AudioFormat
    let bitrateKbps: Int  // 0 for lossless (not meaningful)
}

enum AudioFormat: Sendable {
    case mp3
    case aac
    case alac
    case flac
    case wav
    case aiff
    case unknown(extension: String)

    var isLossless: Bool {
        switch self {
        case .wav, .flac, .alac, .aiff: return true
        default: return false
        }
    }
}

// In AudioMetadataReader.read(from:):
func readFormatInfo(from url: URL) async throws -> (AudioFormat, Int) {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.load(.tracks)

    guard let audioTrack = tracks.first(where: { $0.mediaType == .audio }) else {
        // Infer from extension only
        return (formatFromExtension(url.pathExtension), 0)
    }

    let estimatedDataRate = try await audioTrack.load(.estimatedDataRate)
    let bitrateKbps = Int(estimatedDataRate / 1000)

    // Check format descriptions for codec identification
    let formatDescriptions = try await audioTrack.load(.formatDescriptions)
    if let formatDesc = formatDescriptions.first {
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        if let formatID = asbd?.pointee.mFormatID {
            switch formatID {
            case kAudioFormatMPEGLayer3:
                return (.mp3, bitrateKbps)
            case kAudioFormatMPEG4AAC:
                return (.aac, bitrateKbps)
            case kAudioFormatAppleLossless:
                return (.alac, 0)
            case kAudioFormatLinearPCM:
                // Could be WAV or AIFF — distinguish by extension
                let ext = url.pathExtension.lowercased()
                let format: AudioFormat = (ext == "wav") ? .wav : .aiff
                return (format, 0)
            case kAudioFormatFLAC:
                return (.flac, 0)
            default:
                return (formatFromExtension(url.pathExtension), bitrateKbps)
            }
        }
    }

    return (formatFromExtension(url.pathExtension), bitrateKbps)
}

func formatFromExtension(_ ext: String) -> AudioFormat {
    switch ext.lowercased() {
    case "mp3": return .mp3
    case "m4a", "aac": return .aac  // default m4a to AAC; overridden by formatDesc check
    case "flac": return .flac
    case "wav": return .wav
    case "aiff", "aif": return .aiff
    default: return .unknown(extension: ext)
    }
}
```

### ffmpeg Conversion Command

Verified on ffmpeg 8.0.1 (Homebrew, Apple Silicon):

```bash
ffmpeg -i input.mp3 -f aiff -acodec pcm_s16be -y output.aiff
```

- `-f aiff` — output format: Audio IFF
- `-acodec pcm_s16be` — codec: PCM signed 16-bit big-endian (standard AIFF encoding)
- `-y` — overwrite output without asking (for temp file pattern)
- No `-ar` flag needed — ffmpeg preserves source sample rate by default (typically 44100 or 48000)
- No `-ac` flag needed — ffmpeg preserves source channel count

The encoder `pcm_s16be` is built into all ffmpeg builds (no optional library needed). Confirmed available via `ffmpeg -h encoder=pcm_s16be`.

### Quality Tier Resolution

```swift
func resolveTier(format: AudioFormat, bitrateKbps: Int) -> QualityTier? {
    switch format {
    case .wav:  return .wav
    case .flac: return .flac
    case .alac: return .alac
    case .aiff: return .aiff
    case .mp3:
        if bitrateKbps >= 320 { return .mp3_320 }
        if bitrateKbps >= 128 { return .mp3_128 }
        return nil  // below minimum known tier
    case .aac:
        if bitrateKbps >= 256 { return .aac_256 }
        return nil  // below minimum known tier
    case .unknown:
        return nil  // unknown formats → low quality
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `Process.launchPath` + `launch()` | `Process.executableURL` + `run()` | Swift 4.2+ | `launchPath`/`launch()` deprecated; use `executableURL`/`run()` |
| `AVAsset` synchronous properties | `AVAsset.load(.tracks)` async | macOS 12+ | Synchronous property access deprecated; must use async `load()` |
| `NSTask` | `Process` | Swift 3 | Name change only; same class |
| Manual concurrency with GCD | Swift `actor` + structured concurrency | Swift 5.5+ | Project already uses actors; consistent approach |

**Deprecated/outdated:**
- `AVAsset.tracks` (synchronous) → use `AVAsset.load(.tracks)` (async, macOS 12+)
- `AVAssetTrack.formatDescriptions` (synchronous) → use `AVAssetTrack.load(.formatDescriptions)` (async)
- `Process.launch()` → use `Process.run()` (Swift 4.2+)

## Open Questions

1. **ALAC detection reliability via formatDescriptions**
   - What we know: `kAudioFormatAppleLossless` (0x616C6163) identifies ALAC codec in `.m4a` containers
   - What's unclear: Edge cases with very old `.m4a` files or non-standard containers
   - Recommendation: Test with real ALAC files; fall back to treating `.m4a` as AAC if formatDescriptions is empty (conservative, per rounding-down decision)

2. **ffmpeg stderr buffer size for audio conversion**
   - What we know: Audio-only conversion produces small stderr output (format info + single progress line)
   - What's unclear: Whether very long files or unusual codecs produce more output
   - Recommendation: Read stderr after termination — safe for audio workloads. Add a timeout (e.g., 5 minutes per file) to prevent infinite hangs.

3. **Conversion pool `defer` + actor re-entrancy**
   - What we know: `defer` blocks are synchronous, so `await pool.release()` can't be called directly
   - What's unclear: Whether wrapping in `Task {}` introduces any timing issues
   - Recommendation: Use explicit `do/catch` instead of `defer` for release, or use a `withSlot` helper method on the actor that takes a closure.

## Sources

### Primary (HIGH confidence)
- **ffmpeg 8.0.1** — Verified locally: pcm_s16be encoder available, AIFF format supported, tested command syntax
- **Apple AVFoundation docs** — `AVAssetTrack.load(.estimatedDataRate)`, `AVAssetTrack.load(.formatDescriptions)`, `CMAudioFormatDescriptionGetStreamBasicDescription`
- **Apple Foundation docs** — `Process` class (run/terminationHandler), `FileHandle`, `ProcessInfo.processorCount`
- **CoreAudioTypes** — `kAudioFormatMPEGLayer3`, `kAudioFormatMPEG4AAC`, `kAudioFormatAppleLossless`, `kAudioFormatLinearPCM`, `kAudioFormatFLAC` constants

### Secondary (MEDIUM confidence)
- Swift concurrency actor semaphore pattern — established community pattern; confirmed by project's existing MusicLibraryIndex actor usage

### Tertiary (LOW confidence)
- None — all findings verified against local tools and official APIs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components are Foundation/AVFoundation APIs or ffmpeg CLI, verified locally
- Architecture: HIGH — patterns follow existing project conventions (actors, async/await, FileTask protocol)
- Pitfalls: HIGH — pipe deadlock, m4a ambiguity, and estimatedDataRate=0 are well-documented issues; process termination handler threading is standard Swift knowledge

**Research date:** 2026-02-22
**Valid until:** 2026-04-22 (stable domain — AVFoundation and ffmpeg CLI are mature)
