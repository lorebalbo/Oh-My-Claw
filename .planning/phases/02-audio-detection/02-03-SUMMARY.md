---
phase: 02-audio-detection
plan: "03"
subsystem: audio
tags: [integration, unit-tests, AppCoordinator, event-routing]

requires:
  - phase: 02-audio-detection
    provides: AudioFileIdentifier, AudioMetadataReader, MusicLibraryIndex, AudioTask
provides:
  - End-to-end audio pipeline wired through AppCoordinator
  - Task routing infrastructure extensible for PDF (Phase 4)
  - 19 unit tests for audio detection components
affects: [03-01, 04-02, 05-01]

tech-stack:
  added: []
  patterns: [task-routing event loop, protocol-based extensibility]

key-files:
  created:
    - Tests/AudioDetectionTests.swift
  modified:
    - OhMyClaw/App/AppCoordinator.swift

key-decisions:
  - "Tasks array for extensibility — new FileTask types register without changing event loop"
  - "First-match routing: first enabled task that canHandle takes ownership"
  - "MusicLibraryIndex built before watcher starts — index ready before events flow"

patterns-established:
  - "Task routing: for task in tasks where task.isEnabled && task.canHandle → process → switch result"
  - "Unit tests: struct-level testing without I/O or real files"

requirements-completed: [AUD-01, AUD-02, AUD-03, AUD-04, AUD-05, AUD-06]

duration: 5min
completed: 2026-02-22
---

# Plan 02-03: AppCoordinator Integration & Unit Tests

**AppCoordinator builds music library index at launch, routes file events through AudioTask pipeline, and 19 unit tests verify audio detection components in isolation.**

## What Was Built

### AppCoordinator Integration (`OhMyClaw/App/AppCoordinator.swift`)
- Added `musicLibraryIndex: MusicLibraryIndex?` and `tasks: [any FileTask]` properties for extensible task routing
- In `start()`: creates MusicLibraryIndex, builds index from ~/Music (expanded from `config.audio.destinationPath`), creates AudioTask with all dependencies (AudioFileIdentifier, AudioMetadataReader, MusicLibraryIndex, AudioConfig), appends to tasks array if audio is enabled, logs "Audio pipeline ready"
- Index is built BEFORE watcher starts — guarantees dedup index is ready before file events arrive
- Replaced Phase 1 TODO with task routing loop: iterates `tasks` where `isEnabled && canHandle`, calls `process`, switches on all 4 `TaskResult` cases with structured logging, breaks after first match, logs unhandled files at debug level

### Unit Tests (`Tests/AudioDetectionTests.swift`)
- **AudioFileIdentifierTests (9 tests):** recognizes mp3/m4a/flac/wav/aiff/aif, rejects non-audio/no-extension/temp extensions, case-insensitive matching
- **AudioMetadataTests (5 tests):** hasRequiredFields with all present/missing title/subset/empty list, missingFields returns correct names
- **MusicLibraryIndexTests (5 tests):** add+contains, contains false for missing, normalization trims+lowercases, remove, different keys don't collide

### No deviations from plan
Both tasks implemented exactly as specified. The @MainActor Task inherits actor context so `self.tasks` access works naturally.

## Self-Check: PASSED
- Build succeeded with zero errors
- 40 tests executed, 0 failures (19 new + 21 existing)
- AppCoordinator imports and uses AudioTask, AudioFileIdentifier, AudioMetadataReader, MusicLibraryIndex
- MusicLibraryIndex.build called before startMonitoring()
- Event loop routes through tasks array with TaskResult switch covering all 4 cases
- TODO comment fully replaced with working task routing code
