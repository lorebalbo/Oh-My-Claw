---
phase: 01-app-foundation
plan: "03"
subsystem: core
requirements-completed:
  - WATCH-01
  - WATCH-02
  - WATCH-03
duration: ~7min
completed: 2026-02-21
---

# Plan 01-03 Summary

FSEvents-based FileWatcher with per-file debounce, file size stability checks, temp/hidden file filtering, and FileTask protocol for extensible task modules.

## Performance

| Metric | Value |
|--------|-------|
| Tasks completed | 2/2 |
| Duration | ~7 min |
| Deviations | 1 (minor — actor isolation fix) |
| Blockers | 0 |

## Accomplishments

1. **URL+Extensions** — `isHiddenFile`, `isTemporaryDownload`, `shouldBeIgnored`, `fileSize`, `fileExists`, `isDirectory`, `downloadsDirectory` static property
2. **FileTask protocol** — `id`, `displayName`, `isEnabled`, `canHandle(file:)`, `process(file:)` with `TaskResult` enum (`processed`, `skipped`, `duplicate`, `error`)
3. **FileWatcher** — FSEvents C API wrapper using `Unmanaged` to bridge callback, produces `AsyncStream<URL>` of stable files after debounce + filtering
4. **FileDebouncer actor** — Per-file `Task`-based debounce (3s default), file size stability check (500ms between two reads), auto re-debounce if file still changing
5. **FileEvent struct** — `isFileAppeared` and `isFileRemoved` computed from FSEventStreamEventFlags
6. **scanExistingFiles()** — Emits existing non-temp, non-hidden, top-level files without debounce
7. **FileWatcherTests** — URL extension tests, FileEvent flag tests, initialization tests, scan filtering test with temp directory isolation

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | `266d234` | FileWatcher, FileDebouncer, FileTask protocol, URL extensions |
| Task 2 | `f600081` | Unit tests for URL extensions, FileEvent, scan filtering |

## Files Created

- `OhMyClaw/Infrastructure/Extensions/URL+Extensions.swift` — URL convenience properties for file filtering
- `OhMyClaw/Core/Protocols/FileTask.swift` — FileTask protocol + TaskResult enum
- `OhMyClaw/Core/FileWatcher.swift` — FileWatcher (FSEvents), FileDebouncer (actor), FileEvent (struct)
- `Tests/FileWatcherTests.swift` — 11 unit tests covering extensions, events, initialization, scan

## Files Modified

None (all new files).

## Decisions

| Decision | Rationale |
|----------|-----------|
| `FileDebouncer` as actor | Serializes access to pendingTasks dictionary; Tasks are created per-file for independent debounce timers |
| `FileWatcher` as `@unchecked Sendable` | Manages own synchronization via eventQueue + FileDebouncer actor; standard pattern for FSEvents wrappers |
| `cancelAll()` as nonisolated with inner Task | Called from synchronous `stop()` context; wraps actor-isolated cleanup in a Task |
| 0.5s FSEvents latency | Batches raw events before callback fires; distinct from the 3s per-file debounce |
| Re-debounce on unstable size | If file size differs between two reads, re-enters debounce cycle rather than dropping the file |

## Deviations

| # | Type | Description | Resolution |
|---|------|-------------|------------|
| 1 | Bug | Plan's `handleRawEvent` called actor-isolated `debounce()` synchronously — Swift compiler error | Wrapped call in `Task { await ... }`; also made `cancelAll()` nonisolated with inner Task for `stop()` compatibility |

## Self-Check

- [x] `OhMyClaw/Core/FileWatcher.swift` exists on disk (8537 bytes)
- [x] `OhMyClaw/Core/Protocols/FileTask.swift` exists on disk (1144 bytes)
- [x] `OhMyClaw/Infrastructure/Extensions/URL+Extensions.swift` exists on disk (1645 bytes)
- [x] `Tests/FileWatcherTests.swift` exists on disk (5715 bytes)
- [x] `git log` shows both commits for plan 01-03
- [x] Main source files pass `xcrun swiftc -typecheck` (zero errors)
- [x] XCTest unavailable without Xcode.app — test syntax verified structurally

**Result: PASSED**
