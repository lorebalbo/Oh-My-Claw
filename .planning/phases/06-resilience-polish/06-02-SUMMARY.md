---
phase: 06-resilience-polish
plan: "02"
subsystem: config-reload, sleep-wake
tags: [config, hot-reload, dispatchsource, sleep-wake, resilience]
requires: [06-01]
provides: [config-file-watcher, reload-semantics, sleep-wake-recovery]
affects: [ConfigStore, AppCoordinator, config-pipeline]
key-files:
  - OhMyClaw/Config/ConfigFileWatcher.swift
  - OhMyClaw/Config/ConfigStore.swift
  - OhMyClaw/App/AppCoordinator.swift
key-decisions:
  - "DispatchSource.makeFileSystemObjectSource with [.write, .rename, .delete] for atomic save detection"
  - "500ms debounce via cancellable Task to collapse rapid editor writes"
  - "Restart (re-open fd) on .delete/.rename to track new inode after atomic save"
  - "ReloadResult enum (.unchanged, .updated, .invalid) for rich feedback to caller"
  - "Keep-old-on-invalid semantics — invalid config edits preserve last-known-good config, never reset to defaults"
  - "Equatable comparison on AppConfig detects no-ops (user saved without changes)"
  - "Sleep/wake via NSWorkspace notification async sequences, not NotificationCenter.default"
  - "willSleep flushes ErrorCollector before teardown; didWake resets cooldowns for fresh reporting"
  - "didWake calls startMonitoring() which re-scans ~/Downloads for files that arrived during sleep"
  - "rebuildTaskPipeline creates entirely new task instances — in-flight tasks unaffected"
  - "Used OpenAIClient (not LMStudioClient) matching actual codebase API"
requirements-completed: [CFG-05, INF-04]
duration: ~6 min
completed: 2026-02-22
---

# Plan 06-02 Summary: Config Hot-Reload & Sleep/Wake Recovery

Config changes from any external editor take effect immediately via DispatchSource file monitoring with atomic-save handling, and file monitoring resumes seamlessly after macOS sleep/wake cycles.

## Performance
- 3 tasks completed in ~6 minutes
- Zero build errors, all existing tests pass
- One new file created, two files modified

## Accomplishments
1. **ConfigFileWatcher** — DispatchSource-based single-file watcher with [.write, .rename, .delete] mask, 500ms debounce, and automatic fd re-open on atomic saves (inode replacement)
2. **ConfigStore.reload()** — New method with ReloadResult enum providing three outcomes: unchanged (no-op), updated (apply + notify), invalid (keep old config, report errors). Public configFileURL accessor and internal validate() for testability
3. **AppCoordinator integration** — Config file watcher lifecycle (start in start(), stop in stopMonitoring()), handleConfigChange() routing all three ReloadResult cases, rebuildTaskPipeline() creating fresh AudioTask/PDFTask with updated config, sleep/wake observers via NSWorkspace async notification sequences, handleWillSleep() teardown (flush errors, cancel event loop, stop watchers), handleDidWake() recovery (reset cooldowns, restart monitoring + re-scan ~/Downloads, restart config watcher)

## Task Commits
| # | Task | Commit |
|---|------|--------|
| 1 | ConfigFileWatcher with DispatchSource and atomic save handling | `7e7366e` |
| 2 | ConfigStore.reload() with keep-old-on-invalid semantics and ReloadResult enum | `98a595b` |
| 3 | Config file watcher integration and sleep/wake recovery in AppCoordinator | `faeb241` |

## Files
| File | Action | Description |
|------|--------|-------------|
| OhMyClaw/Config/ConfigFileWatcher.swift | Created | DispatchSource-based file watcher with atomic save handling and debounce |
| OhMyClaw/Config/ConfigStore.swift | Modified | Added ReloadResult enum, reload() method, configFileURL property, internal validate() |
| OhMyClaw/App/AppCoordinator.swift | Modified | Config watcher lifecycle, sleep/wake handlers, task pipeline rebuild |
| OhMyClaw.xcodeproj/project.pbxproj | Modified | Added ConfigFileWatcher.swift to project |

## Decisions
- **DispatchSource over FSEventsStreamCreate**: DispatchSource is the appropriate API for single-file monitoring; FSEvents is for directory trees
- **Restart on inode change**: Atomic saves (rename/delete) replace the inode, so we close the old fd, wait 100ms, and re-open to track the new file
- **Keep-old-on-invalid**: Invalid config edits during hot-reload preserve the last-known-good config rather than resetting to defaults — safer for the user
- **OpenAIClient instead of LMStudioClient**: Plan template referenced LMStudioClient but actual codebase uses OpenAI API — adapted accordingly
- **No health polling**: Skipped healthPolling/healthPollingTask references from plan since they don't exist in the codebase

## Deviations
- Plan referenced `LMStudioClient`, `lmStudioPort`, `modelName`, `healthPollingTask`, `startHealthPolling()`, and `appState.lmStudioAvailable` — all replaced with `OpenAIClient`, `openaiApiKey`, `openaiModel`, and `appState.openaiApiKeyConfigured` matching the actual codebase
- Removed health polling logic from handleDidWake() and rebuildTaskPipeline() since it doesn't exist in the current implementation

## Issues
None.

## Next Phase Readiness
This completes Phase 6 (Resilience & Polish) and the entire project roadmap. All 32 v1 requirements are satisfied:
- CFG-05: Config changes from any source take effect immediately without restart
- INF-04: File monitoring resumes after macOS sleeps
- All prior requirements (APP-01..05, WATCH-01..03, AUD-01..11, PDF-01..04, CFG-01..04, INF-01..03) completed in phases 1-6
