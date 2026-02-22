---
phase: 03-audio-conversion
plan: "01"
subsystem: audio
tags: [ffmpeg, process, concurrency, actor]

requires:
  - phase: 02-audio-detection
    provides: AudioTask pipeline, MusicLibraryIndex actor pattern
provides:
  - FFmpegLocator for binary path detection at launch
  - FFmpegConverter for async AIFF 16-bit conversion via Process
  - ConversionPool actor for CPU-bounded concurrent conversions
affects: [03-03-integration]

tech-stack:
  added: [Process, Pipe, CheckedContinuation]
  patterns: [async Process wrapper via terminationHandler + withCheckedThrowingContinuation, actor-based semaphore with waiters array]

key-files:
  created:
    - OhMyClaw/Audio/FFmpegService.swift
    - OhMyClaw/Audio/ConversionPool.swift
  modified:
    - OhMyClaw.xcodeproj/project.pbxproj

key-decisions:
  - "UUID-prefixed temp files in system temp directory instead of .aiff.tmp alongside output to avoid race conditions"
  - "Stderr read after process termination to prevent pipe deadlock"

patterns-established:
  - "Async Process wrapper: withCheckedThrowingContinuation + terminationHandler bridges Process to async/await"
  - "Actor semaphore: CheckedContinuation waiters array for bounded concurrency"

requirements-completed: [INF-01, AUD-08, AUD-09]

duration: 2min
completed: 2026-02-22
---

# Phase 3 Plan 01: ffmpeg Service & Conversion Pool Summary

**FFmpegLocator detects ffmpeg at known Homebrew paths or PATH, FFmpegConverter wraps Process as async with temp file protection, ConversionPool actor bounds concurrent conversions to CPU core count.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-22T13:32:55Z
- **Completed:** 2026-02-22T13:35:32Z
- **Tasks:** 2 completed
- **Files modified:** 3

## Accomplishments
- FFmpegLocator.locate() searches Apple Silicon → Intel → PATH in order, returning first found executable
- FFmpegConverter.convert() runs ffmpeg as async Process with UUID-prefixed temp files and atomic rename on success
- ConversionPool actor implements bounded concurrency using CheckedContinuation waiters array

## Task Commits

Each task was committed atomically:

1. **Task 1: FFmpegLocator & FFmpegConverter** - `a157620` (feat)
2. **Task 2: ConversionPool actor** - `88ed2ad` (feat)

## Files Created/Modified
- `OhMyClaw/Audio/FFmpegService.swift` - FFmpegLocator, FFmpegConverter, ConversionError
- `OhMyClaw/Audio/ConversionPool.swift` - ConversionPool actor with bounded concurrency
- `OhMyClaw.xcodeproj/project.pbxproj` - Added new files to Xcode project

## Decisions Made
- UUID-prefixed temp files in system temp directory (instead of `.aiff.tmp` alongside output) to avoid race conditions between files with the same name
- Stderr read after process termination to prevent pipe deadlock (safe for audio-only conversion)

## Deviations from Plan

None - plan executed exactly as written.

## Verification
- Both new files compile without errors (BUILD SUCCEEDED)
- FFmpegLocator searches Apple Silicon path first, then Intel, then PATH
- FFmpegConverter uses UUID temp file pattern in system temp directory
- FFmpegConverter reads stderr AFTER process termination
- ConversionPool defaults to ProcessInfo.processInfo.processorCount
- All types are Sendable (structs and actor)

## Next
Ready for 03-02 (Quality models & metadata extension).
