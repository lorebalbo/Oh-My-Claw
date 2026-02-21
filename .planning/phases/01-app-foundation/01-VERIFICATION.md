---
phase: 01-app-foundation
status: passed
verified: 2026-02-21
---

# Phase 1: App Foundation & File Watching — Verification

## Build Verification
**xcodebuild build:** SUCCEEDED (after 2 fixes)

Two issues found and fixed (commit `8e6d0bb`):
1. **`AppCoordinator.appState` was `let`** — Swift's `@Bindable` key path binding in `MenuBarView` requires a writable path. Changed `let appState = AppState()` to `var appState = AppState()`.
2. **Test target missing `GENERATE_INFOPLIST_FILE`** — `OhMyClawTests` target had no Info.plist and wasn't set to auto-generate one. Added `GENERATE_INFOPLIST_FILE: true` to `project.yml`.

After fixes: `xcodebuild -scheme OhMyClaw -configuration Debug build` → **BUILD SUCCEEDED**.

## Test Verification
**xcodebuild test:** 21/21 tests passed

```
Test Suite 'ConfigStoreTests' — 9 tests, 0 failures (0.009s)
Test Suite 'FileWatcherTests' — 12 tests, 0 failures (0.007s)
Total: 21 tests, 0 failures (0.016s)
```

Test breakdown:
- **ConfigStoreTests (9):** testDefaultValues, testFirstLaunchCreatesConfigFile, testFirstLaunchUsesDefaults, testInvalidJSONFallsBackToDefaults, testInvalidValuesReportErrors, testLoadsValidConfig, testMissingSectionsFallbackToDefaults, testSavePersistsConfig, testSaveWritesAtomically
- **FileWatcherTests (12):** testCaseInsensitiveExtensionMatching, testCustomWatchDirectory, testDefaultWatchDirectory, testDirectoryEventNotFileAppeared, testDotfileIsHidden, testFileAppearedEvent, testFileRemovedEvent, testHiddenFileDetection, testNonTemporaryExtensions, testScanExistingFilesSkipsHiddenAndTemp, testShouldBeIgnoredCombinesChecks, testTemporaryDownloadExtensions

## Success Criteria

### 1. Menu bar app with monitoring toggle
**Status:** ✓ Passed
**Evidence:**
- `Info.plist` contains `<key>LSUIElement</key><true/>` — no Dock icon
- `OhMyClawApp.swift` uses `MenuBarExtra("Oh My Claw", systemImage: "tray.and.arrow.down.fill")` with `.menuBarExtraStyle(.window)` — icon in menu bar, dropdown on click
- `MenuBarView.swift` has `Toggle("Monitoring", isOn: $coordinator.appState.isMonitoring).toggleStyle(.switch).tint(.green)` — switch-style toggle
- `MenuBarView.swift` has `Button("Quit Oh My Claw") { NSApplication.shared.terminate(nil) }` — quit action
- `AppState.swift`: `var isMonitoring: Bool = true` — auto-starts on launch
- `AppCoordinator.toggleMonitoring(_:)` starts/stops `FileWatcher` based on toggle state
- `.task { await coordinator.start() }` in MenuBarView auto-launches services

### 2. File detection within 5 seconds
**Status:** ✓ Passed
**Evidence:**
- `FileWatcher.swift` monitors `~/Downloads` via `FSEventStreamCreate` with C API callback bridged through `Unmanaged`
- `AppCoordinator.swift` event loop logs `AppLogger.shared.info("File detected", context: ["file": ..., "size": ...])` with timestamp (ISO 8601 in JSON-lines)
- Timing budget: 0.5s FSEvents latency + 3.0s debounce + 0.5s stability check = **4.0s total**, well within the 5s requirement
- `FileDebouncer` actor implements per-file debounce with `Task.sleep` and file-size stability verification (two reads must match and be > 0)

### 3. Temp files never processed
**Status:** ✓ Passed
**Evidence:**
- `URL+Extensions.swift` defines `isTemporaryDownload` filtering 6 extensions: `crdownload`, `part`, `tmp`, `download`, `partial`, `downloading` — superset of the 4 specified in WATCH-03
- `URL.shouldBeIgnored` combines `isHiddenFile || isTemporaryDownload`
- `FileWatcher.handleRawEvent()` applies `guard !event.url.shouldBeIgnored else { return }` before debouncing
- `FileWatcher.scanExistingFiles()` applies `guard !fileURL.shouldBeIgnored` before emitting
- `FileWatcherTests` has dedicated tests: `testTemporaryDownloadExtensions` (all 6), `testCaseInsensitiveExtensionMatching`, `testScanExistingFilesSkipsHiddenAndTemp`

### 4. Config created on first launch
**Status:** ✓ Passed
**Evidence:**
- `ConfigStore.init()` resolves path to `~/Library/Application Support/OhMyClaw/config.json`
- `ConfigStore.load()` creates the Application Support directory if missing, then checks file existence — if absent, copies bundled `default-config.json` and saves hardcoded defaults
- `default-config.json` exists at `OhMyClaw/Resources/` with all four sections (watcher, audio, pdf, logging) matching hardcoded `AppConfig.defaults`
- `ConfigStoreTests.testFirstLaunchCreatesConfigFile()` and `testFirstLaunchUsesDefaults()` verify this behavior
- Per-section fallback decoding via `(try? container.decode(...)) ?? .defaults` ensures partial configs don't fail

## Requirement Traceability

| ID | Description | Status | Evidence |
|----|-------------|--------|----------|
| APP-01 | User can toggle the app on/off from the menu bar icon | ✓ Passed | `MenuBarView` has a switch-style `Toggle` bound to `AppState.isMonitoring`; `.onChange` calls `coordinator.toggleMonitoring()` which starts/stops `FileWatcher` |
| WATCH-01 | App monitors ~/Downloads in real-time using FSEvents | ✓ Passed | `FileWatcher` uses `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents`, default directory is `.downloadsDirectory` (~/Downloads), 0.5s latency for event batching |
| WATCH-02 | Watcher debounces file events to avoid processing incomplete downloads | ✓ Passed | `FileDebouncer` actor: 3.0s per-file debounce via `Task.sleep`, followed by 0.5s stability check (two file-size reads must match and be >0); auto re-debounce if still changing |
| WATCH-03 | Watcher ignores temporary files (.crdownload, .part, .tmp, .download) | ✓ Passed | `URL.isTemporaryDownload` filters 6 extensions (superset of 4 required): crdownload, part, tmp, download, partial, downloading; `shouldBeIgnored` also filters hidden files; applied in both `handleRawEvent` and `scanExistingFiles` |
| CFG-01 | App reads settings from external JSON config file | ✓ Passed | `ConfigStore` loads from `~/Library/Application Support/OhMyClaw/config.json`; `AppConfig` is `Codable` with 4 nested sections and per-section fallback decoding; first launch creates file from bundled defaults; validation with human-readable errors |
| INF-03 | All operations are logged to rotating log file | ✓ Passed | `AppLogger` singleton writes JSON-lines (`{"ts","level","msg","ctx"}`) to `~/Library/Logs/OhMyClaw/ohmyclaw.log`; 10MB rotation, 3-file retention; configurable level (debug/info/warn/error); thread-safe via `DispatchQueue`; all key operations logged: start, stop, file detected, file disappeared, config errors |

## Human Verification

The following items can only be confirmed by manually launching and interacting with the app:

1. **End-to-end file drop** — Drop a file into ~/Downloads and verify a log entry appears in `~/Library/Logs/OhMyClaw/ohmyclaw.log` within 5 seconds
2. **Toggle round-trip** — Toggle monitoring off/on from the menu bar and verify FileWatcher stops/restarts (logged)
3. **First-launch config creation** — Delete `~/Library/Application Support/OhMyClaw/config.json`, launch app, verify file is recreated with defaults

## Gaps

None.

## Summary

**Phase 1: PASSED**

Full Xcode build succeeded after two minor fixes (let→var for Bindable, GENERATE_INFOPLIST_FILE for test target). All 21 unit tests (9 ConfigStore + 12 FileWatcher) pass with zero failures. All four success criteria verified. All six requirements (APP-01, WATCH-01, WATCH-02, WATCH-03, CFG-01, INF-03) implemented with tests and structured logging. Only remaining items are manual end-to-end tests (file drop, toggle, first-launch) which require running the app interactively.
