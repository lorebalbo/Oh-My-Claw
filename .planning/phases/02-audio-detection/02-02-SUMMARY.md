---
phase: 02-audio-detection
plan: "02"
subsystem: audio
tags: [actor, duplicate-detection, pipeline, FileTask, FileManager]

requires:
  - phase: 02-audio-detection
    provides: AudioFileIdentifier, AudioMetadataReader, AudioMetadata
provides:
  - MusicLibraryIndex actor for thread-safe duplicate detection
  - AudioTask implementing full FileTask pipeline
  - Duplicate detection via normalized title|artist key
  - Filename conflict routing to possible_duplicate/
affects: [02-03, 03-02]

tech-stack:
  added: []
  patterns: [actor-based concurrency, bounded TaskGroup, FileTask pipeline pattern]

key-files:
  created:
    - OhMyClaw/Audio/MusicLibraryIndex.swift
    - OhMyClaw/Audio/AudioTask.swift  
  modified: []

key-decisions:
  - "Actor for MusicLibraryIndex — thread safety without manual locking"
  - "Bounded concurrency (max 8) for metadata reads during index build"
  - "Integer duration comparison: Int(durationSeconds) < minDurationSeconds"
  - "Filename conflicts routed to possible_duplicate/ instead of overwrite"

patterns-established:
  - "FileTask pipeline: canHandle gate → multi-step process with early returns"
  - "Actor-based shared mutable state with normalized key indexing"

requirements-completed: [AUD-02, AUD-03, AUD-04, AUD-05, AUD-06]

duration: 5min
completed: 2026-02-22
---

# Plan 02-02: Music Library Index & AudioTask Pipeline

**MusicLibraryIndex actor indexes ~/Music with bounded concurrent reads; AudioTask orchestrates the full detect→validate→filter→deduplicate→move pipeline via FileTask protocol.**

## What Was Built

### MusicLibraryIndex (`OhMyClaw/Audio/MusicLibraryIndex.swift`)
- Swift actor with `private var index: [String: URL]` keyed by normalized "title|artist" (trimmed + lowercased)
- `build(from:)` recursively enumerates a music directory, identifies audio files via `AudioFileIdentifier`, reads metadata with `withTaskGroup` bounded to 8 concurrent reads, and populates the index. Logs count and elapsed time at INFO level.
- `contains(title:artist:)` and `url(for:artist:)` for duplicate queries
- `add(title:artist:url:)` and `remove(title:artist:)` for index mutation
- Private `normalizeKey(title:artist:)` static method for consistent key generation

### AudioTask (`OhMyClaw/Audio/AudioTask.swift`)
- `struct AudioTask: FileTask, Sendable` with `id = "audio"`, `displayName = "Audio Detection"`
- `canHandle(file:)` delegates to `AudioFileIdentifier.isRecognizedAudioFile`
- `process(file:)` implements the 5-step pipeline:
  1. **Read metadata** — returns `.error` on failure
  2. **Validate required fields** (AUD-02) — checks `config.requiredMetadataFields`, returns `.skipped` with missing fields logged
  3. **Check duration** (AUD-03) — `Int(durationSeconds) < config.minDurationSeconds`, returns `.skipped`
  4. **Check duplicates** (AUD-04/AUD-05) — queries `MusicLibraryIndex.contains`, deletes incoming file and returns `.duplicate`
  5. **Move to ~/Music** (AUD-06) — expands `config.destinationPath` via NSString, handles filename conflicts by routing to `possible_duplicate/` subdirectory, updates library index
- Error handling wraps FileManager ops in do/catch with specific CocoaError.fileWriteNoPermission handling

### No deviations from plan
Both files implemented exactly as specified. project.pbxproj updated to include both new files in the Audio group and Sources build phase.

## Self-Check: PASSED
- Both files compile successfully (`xcodebuild build` succeeded with no errors)
- MusicLibraryIndex is an actor with build, contains, url, add, remove methods
- MusicLibraryIndex.build uses withTaskGroup with max 8 concurrent reads (seed 8, await one before adding next)
- AudioTask conforms to FileTask protocol (id, displayName, isEnabled, canHandle, process)
- AudioTask.process implements all 5 pipeline steps in order with early returns
- Metadata validation uses config.requiredMetadataFields (not hardcoded)
- Duration comparison uses Int truncation: `Int(metadata.durationSeconds) < config.minDurationSeconds`
- Duplicate detection normalizes with trim+lowercase before comparison
- Filename conflicts route to ~/Music/possible_duplicate/ (not overwrite)
- All results logged at INFO level via AppLogger.shared
