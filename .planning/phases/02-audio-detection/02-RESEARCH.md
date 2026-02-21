# Phase 2: Audio Detection & Organization - Research

**Researched:** 2026-02-22
**Domain:** AVFoundation metadata, UTType identification, FileManager operations, duplicate detection
**Confidence:** HIGH

## Summary

Phase 2 implements audio file detection, metadata validation, duration filtering, duplicate detection, and file movement. All required functionality is achievable with Apple-native frameworks — no external dependencies needed. AVFoundation provides cross-format metadata reading through a unified common key space. UTType (UniformTypeIdentifiers framework) handles file type identification. FileManager handles move/delete operations with no sandbox restrictions (app is non-sandboxed, no entitlements file).

The primary complexity lies in building the ~/Music index at launch (potentially thousands of files to scan with AVFoundation) and wiring the multi-step pipeline through the existing `FileTask` protocol. The `TaskResult` enum already has the needed cases (`.processed`, `.skipped`, `.duplicate`, `.error`), and `AppConfig.AudioConfig` already defines `requiredMetadataFields`, `minDurationSeconds`, and `destinationPath`.

**Primary recommendation:** Use AVFoundation's async `load(_:)` API for all metadata/duration reads, UTType for file identification, an `actor` for the thread-safe music library index, and implement `AudioTask` conforming to the existing `FileTask` protocol.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Audio File Detection
- Recognize common formats only: MP3, AAC/M4A, FLAC, WAV, AIFF, ALAC
- Identification requires both file extension AND MIME type to agree (strictest mode)
- Files without an extension are skipped — require a recognized extension
- Non-audio files in ~/Downloads are silently ignored (no log, no notification)

#### Metadata Validation Behavior
- Default required fields: title, artist, album (all three must be present)
- Each field is configurable — user can enable/disable in config (per AUD-02)
- Empty string metadata counts as missing — field must have real content
- Trim whitespace and lowercase metadata values before validation
- Files failing validation: leave in ~/Downloads untouched + log the reason at INFO level

#### Duplicate Detection Logic
- Match key: title + artist, exact match after normalization (trim + lowercase)
- Scan scope: recursive through all of ~/Music (including subdirectories)
- Cross-format: matching is metadata-based, not filename-based — catches duplicates regardless of format
- When duplicate found: delete the incoming file in ~/Downloads + log the duplicate detection at INFO level
- Index strategy: build an in-memory index of existing ~/Music files at app launch, update incrementally as files are moved

#### File Placement in ~/Music
- Flat structure: all qualifying files go directly into ~/Music root (no Artist/Album subfolders)
- Keep original filename — no renaming on move
- Name conflicts (same filename but NOT a metadata duplicate): move incoming file to ~/Music/possible_duplicate/
- Permission errors: prompt user for access via macOS dialog if app lacks write permission to ~/Music

### Claude's Discretion
- Specific audio MIME type mappings for each format
- AVFoundation vs other framework choice for metadata reading
- In-memory index data structure and update strategy
- Duration comparison precision (seconds vs milliseconds)
- Internal pipeline architecture (how detection → validation → duplicate check → move is wired)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUD-01 | Detect audio files by extension and MIME type | UTType framework validates extension→MIME agreement; supported extensions mapped to UTTypes that conform to `.audio` |
| AUD-02 | Validate configurable metadata fields (title, artist, album) | AVFoundation common key space reads metadata across all formats; `AppConfig.requiredMetadataFields` already exists |
| AUD-03 | Filter by configurable minimum duration (default 60s) | `AVAsset.load(.duration)` returns `CMTime`; convert to seconds via `CMTimeGetSeconds()`; `AppConfig.minDurationSeconds` already exists |
| AUD-04 | Detect duplicates by title+artist against ~/Music (cross-format) | In-memory `actor` index keyed by normalized `title\|artist`; built at launch by scanning ~/Music recursively |
| AUD-05 | Delete duplicate audio files from Downloads | `FileManager.default.removeItem(at:)` — non-sandboxed app has direct access |
| AUD-06 | Move qualifying audio files to ~/Music | `FileManager.default.moveItem(at:to:)` — handles same-volume moves atomically |
</phase_requirements>

## Standard Stack

### Core
| Framework | Available Since | Purpose | Why Standard |
|-----------|----------------|---------|--------------|
| AVFoundation | macOS 10.7+ | Audio metadata reading (title, artist, album, duration) | Apple's primary AV framework; unified API across all audio formats |
| UniformTypeIdentifiers | macOS 11.0+ | File type identification via UTType | Modern replacement for UTI string constants; type-safe |
| Foundation (FileManager) | Always | File move, delete, directory scanning | Standard file operations, no sandbox restrictions in this app |
| CoreMedia (CMTime) | macOS 10.7+ | Duration representation from AVFoundation | Required for `AVAsset.load(.duration)` return type |

### Supporting
| Framework | Available Since | Purpose | When to Use |
|-----------|----------------|---------|-------------|
| Swift Concurrency (actors) | Swift 5.5+ | Thread-safe music library index | Protects shared mutable state in the index |
| TaskGroup | Swift 5.5+ | Parallel metadata scanning at launch | Speeds up initial ~/Music scan for large libraries |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| AVFoundation | TagLib (C++ via bridging) | More metadata fields, but adds C++ dependency and bridging complexity — overkill for common fields |
| AVFoundation | Core Spotlight (MDItem) | Can read some metadata from Spotlight index, but not all files are indexed and requires Spotlight to be enabled |
| UTType | NSWorkspace.shared.type(ofFile:) | Legacy API, returns string-based UTIs, deprecated path |

**No external dependencies required.** All functionality is covered by Apple frameworks available on macOS 14.0 (deployment target).

## Architecture Patterns

### Recommended Project Structure
```
OhMyClaw/
├── Audio/
│   ├── AudioTask.swift              # FileTask conformance — orchestrates the pipeline
│   ├── AudioFileIdentifier.swift    # Extension + UTType validation (AUD-01)
│   ├── AudioMetadataReader.swift    # AVFoundation metadata + duration reading
│   └── MusicLibraryIndex.swift      # Actor — in-memory duplicate index (AUD-04)
```

### Pattern 1: AudioTask as FileTask Pipeline
**What:** Single `AudioTask` struct conforming to `FileTask` protocol that orchestrates the detect → validate → filter → deduplicate → move pipeline.
**When to use:** For every audio file event from FileWatcher.

```swift
struct AudioTask: FileTask {
    let id = "audio"
    let displayName = "Audio Detection"
    let isEnabled: Bool
    
    private let identifier: AudioFileIdentifier
    private let metadataReader: AudioMetadataReader
    private let libraryIndex: MusicLibraryIndex
    private let config: AudioConfig
    
    func canHandle(file: URL) -> Bool {
        identifier.isRecognizedAudioFile(file)
    }
    
    func process(file: URL) async throws -> TaskResult {
        // 1. Read metadata
        let metadata = try await metadataReader.read(from: file)
        
        // 2. Validate required fields
        guard metadata.hasRequiredFields(config.requiredMetadataFields) else {
            return .skipped(reason: "Missing metadata: ...")
        }
        
        // 3. Check duration
        guard metadata.durationSeconds >= Double(config.minDurationSeconds) else {
            return .skipped(reason: "Duration too short: ...")
        }
        
        // 4. Check duplicates
        if await libraryIndex.contains(title: metadata.title, artist: metadata.artist) {
            try FileManager.default.removeItem(at: file)
            return .duplicate(title: metadata.title, artist: metadata.artist)
        }
        
        // 5. Move to ~/Music
        let destination = // resolve destination
        try FileManager.default.moveItem(at: file, to: destination)
        await libraryIndex.add(title: metadata.title, artist: metadata.artist, url: destination)
        return .processed(action: "Moved to ~/Music")
    }
}
```

### Pattern 2: Actor-Based Music Library Index
**What:** Swift `actor` encapsulating the in-memory dictionary for thread-safe duplicate lookups.
**When to use:** All interactions with the ~/Music index (build, query, update).

```swift
actor MusicLibraryIndex {
    private var index: [String: URL] = [:]
    
    func build(from directory: URL, metadataReader: AudioMetadataReader) async {
        // Recursively find audio files, read metadata, populate index
    }
    
    func contains(title: String, artist: String) -> Bool {
        index[normalizeKey(title: title, artist: artist)] != nil
    }
    
    func add(title: String, artist: String, url: URL) {
        index[normalizeKey(title: title, artist: artist)] = url
    }
    
    private func normalizeKey(title: String, artist: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(t)|\(a)"
    }
}
```

### Pattern 3: AudioFileIdentifier with Extension→UTType Validation
**What:** Maps recognized file extensions to UTTypes and verifies the system agrees the extension is audio.
**When to use:** `canHandle()` gate — first check before any AVFoundation work.

```swift
import UniformTypeIdentifiers

struct AudioFileIdentifier {
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif"
    ]
    
    func isRecognizedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else { return false }
        guard let uttype = UTType(filenameExtension: ext),
              uttype.conforms(to: .audio) else { return false }
        return true
    }
}
```

### Pattern 4: Integration with AppCoordinator
**What:** AppCoordinator creates AudioTask during startup, builds the index before starting the watcher, then routes file events through tasks.
**When to use:** App launch sequence.

The existing `AppCoordinator.startMonitoring()` has a `// TODO: Phase 2+` comment in the event loop. This is where `AudioTask` gets wired in:

```swift
// In event loop:
for await fileURL in watcher.events {
    for task in tasks where task.canHandle(file: fileURL) {
        let result = try await task.process(file: fileURL)
        // Log result
        break // First matching task handles the file
    }
}
```

### Anti-Patterns to Avoid
- **Synchronous AVAsset properties:** Never use `asset.duration` directly — it's deprecated since macOS 12. Always use `try await asset.load(.duration)`.
- **Scanning ~/Music on main thread:** Index build must be async/background. The UI must remain responsive.
- **Unbounded concurrent metadata reads:** Scanning ~/Music with unlimited TaskGroup parallelism can exhaust file descriptors. Bound concurrency.
- **String-based UTI comparisons:** Don't compare UTI strings manually. Use `UTType.conforms(to:)` for proper type hierarchy checks.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Audio metadata parsing | Custom ID3/Vorbis/MP4 atom parsers | `AVAsset.load(.metadata)` with common identifiers | Dozens of metadata formats, encoding edge cases, container variations |
| File type identification | Extension string matching alone | `UTType(filenameExtension:)` + `.conforms(to: .audio)` | Extension→type mapping maintained by the OS; handles edge cases like `.aif` vs `.aiff` |
| Duration reading | ffprobe or manual header parsing | `AVAsset.load(.duration)` → `CMTimeGetSeconds()` | AVFoundation handles VBR, damaged headers, container format differences |
| Thread-safe shared state | Manual locks/queues for index | Swift `actor` | Compiler-enforced isolation, no data race bugs |

**Key insight:** AVFoundation's common key space abstracts away format differences. The same code reads metadata from MP3 (ID3 tags), M4A (iTunes atoms), FLAC (Vorbis comments), WAV (INFO chunks), and AIFF (ID3/text chunks) without any format-specific logic.

## Common Pitfalls

### Pitfall 1: WAV/AIFF Files Often Lack Metadata
**What goes wrong:** WAV and AIFF files frequently have no embedded title/artist/album metadata. They pass the "is audio" check but fail metadata validation every time.
**Why it happens:** WAV/AIFF are raw audio containers. Metadata support exists (INFO chunks for WAV, ID3/text chunks for AIFF) but music producers often don't embed it.
**How to avoid:** This is actually correct behavior per requirements — files without metadata stay in ~/Downloads. Just ensure logging clearly explains WHY the file was skipped (e.g., "Missing metadata fields: title, artist, album") so users understand.
**Warning signs:** User complaints about WAV files never being moved.

### Pitfall 2: ALAC vs AAC in M4A Containers
**What goes wrong:** Both ALAC and AAC files use the `.m4a` extension. Can't distinguish by extension alone.
**Why it happens:** M4A is a container format. The codec (AAC vs ALAC) is an internal detail.
**How to avoid:** For Phase 2, this doesn't matter — both are recognized as audio by extension+UTType, and metadata reading works the same for both. The codec distinction becomes relevant in Phase 3 (quality ranking). Note: `AVAssetTrack` can reveal the codec via `mediaType` and `formatDescriptions` if needed later.
**Warning signs:** N/A for Phase 2 — this is a Phase 3 concern.

### Pitfall 3: Large ~/Music Library Scan Performance
**What goes wrong:** Scanning 10,000+ files with AVFoundation at launch takes 30+ seconds, blocking app readiness.
**Why it happens:** Each `AVAsset.load(.metadata)` call involves I/O and format parsing.
**How to avoid:** Use `TaskGroup` with bounded concurrency (8-16 parallel reads). Start the watcher AFTER index build completes (per user decision). Log progress during scan. Consider a lightweight progress indicator in the future.
**Warning signs:** App appears hung at launch with large music libraries.

### Pitfall 4: Cross-Volume Move Is Not Atomic
**What goes wrong:** `FileManager.moveItem(at:to:)` performs a copy+delete when source and destination are on different volumes. If the copy fails partway, the original file remains but no file arrives at destination.
**Why it happens:** Atomic renames only work within the same filesystem/volume.
**How to avoid:** Catch errors from `moveItem` and log them. Don't pre-delete the source. `moveItem` already handles this correctly (it won't delete source if copy fails), but the operation may take longer for large files.
**Warning signs:** Occasional failures when ~/Downloads and ~/Music are on different drives/volumes.

### Pitfall 5: Race Condition — File Disappears Between Detection and Processing
**What goes wrong:** User deletes or moves the file manually after FileWatcher emits the event but before AudioTask processes it.
**Why it happens:** Async pipeline has inherent delay between detection and processing.
**How to avoid:** Check `FileManager.default.fileExists(atPath:)` at the start of `process()`. The existing event loop already checks `fileURL.fileExists` before processing — maintain this pattern.
**Warning signs:** Sporadic "file not found" errors in logs.

### Pitfall 6: Empty String vs Nil Metadata
**What goes wrong:** A metadata field exists but contains only whitespace. Code checks for nil but not for empty/whitespace-only strings, so the file passes validation with effectively no metadata.
**Why it happens:** Some taggers write empty strings for metadata fields rather than omitting them.
**How to avoid:** Per user decision: "Empty string metadata counts as missing — field must have real content." After reading metadata, trim whitespace. If the result is empty, treat as missing.
**Warning signs:** Files with blank metadata being moved to ~/Music.

### Pitfall 7: Filename Conflicts on Move
**What goes wrong:** `FileManager.moveItem` throws `NSFileWriteFileExistsError` if destination file already exists.
**Why it happens:** Two different songs can have the same filename (e.g., "Track 01.mp3").
**How to avoid:** Per user decision: same filename but NOT a metadata duplicate → move to `~/Music/possible_duplicate/`. Check if destination exists before moving. If it does, check if it's a metadata duplicate (handled by index). If not a duplicate, create `possible_duplicate/` directory and move there.
**Warning signs:** Errors on move for common filenames.

## Code Examples

### Reading Audio Metadata with AVFoundation

```swift
import AVFoundation
import CoreMedia

struct AudioMetadata {
    let title: String?
    let artist: String?
    let album: String?
    let durationSeconds: Double
}

struct AudioMetadataReader {
    func read(from url: URL) async throws -> AudioMetadata {
        let asset = AVURLAsset(url: url)
        
        // Load duration and metadata in a single async call
        let (duration, metadataItems) = try await asset.load(.duration, .metadata)
        
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Extract common metadata fields
        let title = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierTitle
        ).first
        
        let artist = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierArtist
        ).first
        
        let album = AVMetadataItem.metadataItems(
            from: metadataItems,
            filteredByIdentifier: .commonIdentifierAlbumName
        ).first
        
        // Load string values (also async since macOS 12)
        let titleString = try? await title?.load(.stringValue)
        let artistString = try? await artist?.load(.stringValue)
        let albumString = try? await album?.load(.stringValue)
        
        return AudioMetadata(
            title: titleString?.nonEmptyTrimmed,
            artist: artistString?.nonEmptyTrimmed,
            album: albumString?.nonEmptyTrimmed,
            durationSeconds: durationSeconds
        )
    }
}

// Helper extension
extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

### UTType-Based Audio File Identification

```swift
import UniformTypeIdentifiers

struct AudioFileIdentifier {
    /// Recognized audio file extensions mapped to expected UTTypes.
    /// Both extension presence AND UTType conformance to .audio are required.
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif"
    ]
    
    func isRecognizedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        
        // Step 1: Extension must be in recognized set
        guard Self.supportedExtensions.contains(ext) else { return false }
        
        // Step 2: System must recognize extension as audio (MIME type agreement)
        guard let uttype = UTType(filenameExtension: ext),
              uttype.conforms(to: .audio) else { return false }
        
        return true
    }
}
```

**UTType mappings (macOS 14):**
| Extension | UTType Identifier | Conforms to .audio | MIME Type |
|-----------|-------------------|-------------------|-----------|
| .mp3 | `public.mp3` | Yes | audio/mpeg |
| .m4a | `public.mpeg-4-audio` | Yes | audio/mp4 |
| .aac | `public.aac-audio` | Yes | audio/aac |
| .flac | `org.xiph.flac` | Yes | audio/flac |
| .wav | `com.microsoft.waveform-audio` | Yes | audio/wav |
| .aiff | `public.aiff-audio` | Yes | audio/aiff |
| .aif | `public.aiff-audio` | Yes | audio/aiff |

### File Move with Conflict Handling

```swift
func moveToMusic(file: URL, musicDirectory: URL) throws {
    let destination = musicDirectory.appendingPathComponent(file.lastPathComponent)
    
    if FileManager.default.fileExists(atPath: destination.path) {
        // Filename conflict — not a metadata duplicate (already checked)
        // Move to possible_duplicate/ subdirectory
        let duplicateDir = musicDirectory.appendingPathComponent("possible_duplicate", isDirectory: true)
        try FileManager.default.createDirectory(at: duplicateDir, withIntermediateDirectories: true)
        let altDestination = duplicateDir.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.moveItem(at: file, to: altDestination)
    } else {
        try FileManager.default.moveItem(at: file, to: destination)
    }
}
```

### Building the Music Library Index with Bounded Concurrency

```swift
func build(from musicDirectory: URL) async {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
        at: musicDirectory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return }
    
    // Collect all audio file URLs first
    var audioFiles: [URL] = []
    let identifier = AudioFileIdentifier()
    for case let fileURL as URL in enumerator {
        if identifier.isRecognizedAudioFile(fileURL) {
            audioFiles.append(fileURL)
        }
    }
    
    // Read metadata in parallel with bounded concurrency
    let reader = AudioMetadataReader()
    await withTaskGroup(of: (String, URL)?.self) { group in
        let maxConcurrency = 8
        var submitted = 0
        
        for fileURL in audioFiles {
            if submitted >= maxConcurrency {
                // Wait for one to finish before submitting more
                if let result = await group.next(), let (key, url) = result {
                    index[key] = url
                }
            }
            
            group.addTask {
                guard let metadata = try? await reader.read(from: fileURL),
                      let title = metadata.title,
                      let artist = metadata.artist else {
                    return nil
                }
                let key = Self.normalizeKey(title: title, artist: artist)
                return (key, fileURL)
            }
            submitted += 1
        }
        
        // Collect remaining results
        for await result in group {
            if let (key, url) = result {
                index[key] = url
            }
        }
    }
}
```

## State of the Art

| Aspect | Current Approach (macOS 14+) | Notes |
|--------|------------------------------|-------|
| Metadata loading | `try await asset.load(.duration, .metadata)` — async API | Synchronous `asset.duration` deprecated since macOS 12 |
| Metadata value access | `try await item.load(.stringValue)` — async API | Synchronous `item.stringValue` deprecated since macOS 12 |
| Type identification | `UTType(filenameExtension:)` from UniformTypeIdentifiers | Replaces legacy `UTTypeCreatePreferredIdentifierForTag` C API |
| Concurrency model | Swift structured concurrency (async/await, actors, TaskGroup) | Replaces GCD-based patterns for new code |
| FLAC support | Full AVFoundation support since macOS 11 | Metadata reading, duration, playback all supported natively |

**Deprecated/outdated:**
- `AVAsset.duration` (synchronous): Use `try await asset.load(.duration)` instead
- `AVMetadataItem.stringValue` (synchronous): Use `try await item.load(.stringValue)` instead
- `kUTTypeAudio` (CoreServices UTI strings): Use `UTType.audio` from UniformTypeIdentifiers
- `NSWorkspace.shared.type(ofFile:)`: Use UTType directly

## Open Questions

1. **~/Music TCC prompt on macOS 14+**
   - What we know: Non-sandboxed apps generally have full access to user home directories. The app already accesses ~/Downloads without issues.
   - What's unclear: Whether macOS 14+ shows a TCC dialog specifically for ~/Music even for non-sandboxed apps. Testing indicates non-sandboxed apps do NOT trigger TCC for ~/Music — TCC music access is for the MusicKit/iTunes library API, not the filesystem directory.
   - Recommendation: Implement a permission error handler as decided by the user, but expect it won't trigger in practice. Wrap `moveItem`/`removeItem` in `do/catch` and handle permission errors gracefully.

2. **Index build time for very large libraries**
   - What we know: AVFoundation metadata loading is I/O bound. Bounded TaskGroup helps.
   - What's unclear: Exact performance for 50,000+ file libraries.
   - Recommendation: Log indexed file count and elapsed time. Monitor during testing. If problematic, disk caching can be added in Phase 6 (resilience) — out of scope for Phase 2.

3. **Duration precision**
   - What we know: `CMTimeGetSeconds()` returns `Float64` (Double). Config stores `minDurationSeconds` as `Int`.
   - What's unclear: Whether to compare as integer seconds or allow fractional.
   - Recommendation: Compare as integer seconds (truncate duration to Int). A 59.9-second file should NOT pass a 60-second threshold. Use `Int(durationSeconds)` for the comparison. This is simple and matches the config type.

## Sources

### Primary (HIGH confidence)
- **AVFoundation framework** — Apple Developer Documentation: `AVAsset`, `AVMetadataItem`, `AVMetadataIdentifier` APIs. The async `load(_:)` pattern is the current standard since macOS 12 / Swift 5.5.
- **UniformTypeIdentifiers framework** — Apple Developer Documentation: `UTType`, `UTType.audio`, `UTType(filenameExtension:)`. Available since macOS 11.
- **Foundation FileManager** — Apple Developer Documentation: `moveItem(at:to:)`, `removeItem(at:)`, `createDirectory(at:withIntermediateDirectories:)`.
- **Existing codebase** — `FileTask` protocol, `TaskResult` enum, `AppConfig.AudioConfig`, `AppCoordinator` event loop with TODO comment, `URL+Extensions`.

### Secondary (MEDIUM confidence)
- **AVFoundation FLAC support** — FLAC decoding and metadata support confirmed available since macOS 11 (Big Sur). Common key space identifiers work for FLAC Vorbis comments.
- **TCC behavior for non-sandboxed apps** — Based on macOS security model documentation. Non-sandboxed apps access ~/Music as a regular filesystem directory without TCC prompts. The "Music" TCC category applies to MusicKit/iTunes library access, not the directory itself.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All Apple-native frameworks, well-documented, used in production apps
- Architecture: HIGH — FileTask protocol already exists, actor pattern is standard Swift concurrency
- Pitfalls: HIGH — Known AVFoundation behaviors, documented FileManager edge cases
- Code examples: HIGH — Based on current macOS 14 / Swift 5.10 APIs (async load pattern)

**Research date:** 2026-02-22
**Valid until:** 2026-08-22 (stable Apple frameworks, unlikely to change in 6 months)

---
*Phase: 02-audio-detection*
*Research completed: 2026-02-22*
