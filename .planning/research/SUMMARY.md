# Project Research Summary

**Project:** Oh My Claw
**Domain:** macOS Menu Bar File Organizer (Audio + PDF classification)
**Researched:** 2026-02-21
**Confidence:** HIGH

## Executive Summary

Oh My Claw is a native macOS menu bar application that automatically organizes files from ~/Downloads. It targets a music-focused power user who wants two things: (1) audio files with proper metadata automatically validated, quality-ranked, converted to AIFF 16-bit via ffmpeg, and moved to ~/Music, and (2) PDF scientific papers classified by a local LLM (LM Studio) and moved to ~/Documents/Papers. The app differentiates from general-purpose file organizers like Hazel by embedding **domain-specific intelligence** — audio quality ranking with format-aware conversion and LLM-powered content classification — rather than relying on user-authored rules.

The recommended stack is entirely native: Swift 5.10+, SwiftUI with `MenuBarExtra` (macOS 13+), FSEvents for file watching, AVFoundation for audio metadata, `Foundation.Process` for ffmpeg execution, and `URLSession` for LM Studio API calls. No external Swift packages are strictly required. The architecture follows a protocol-based task system where `AudioTask` and `PDFTask` conform to a `FileTask` protocol, making the system extensible to future file types without modifying existing code. A pipeline pattern within each task keeps processing steps small, testable, and composable.

The research identifies 20 critical pitfalls, the most dangerous being: incomplete file downloads triggering premature processing (FSEvents fires before write completion), zombie ffmpeg processes from improper lifecycle management, pipe deadlocks with Process I/O, LM Studio API brittleness (unavailable, slow, hallucinating), and macOS killing the menu bar app under memory pressure. These pitfalls directly inform the phased build order — file watcher debouncing, process cleanup, and LLM fault tolerance must be designed into the architecture from day one, not bolted on later.

## Key Findings

### Recommended Stack

**Core:** Swift 5.10+ with Swift Concurrency (`async/await`, `TaskGroup`), SwiftUI for menu bar UI via `MenuBarExtra`, Swift Package Manager for dependencies.

**System Frameworks (zero external deps):**

| Framework | Role |
|---|---|
| FSEvents (CoreServices) | Real-time ~/Downloads monitoring with per-file granularity |
| AVFoundation | Audio metadata reading (duration, title, artist, album, format) |
| AudioToolbox | Fallback codec/bitrate/sample-rate introspection |
| Foundation Process | ffmpeg subprocess execution with async wrapper |
| URLSession | HTTP POST to LM Studio's OpenAI-compatible API (`localhost:1234`) |
| PDFKit | PDF text extraction before LLM classification |
| SMAppService | Launch at Login (macOS 13+, no helper app) |
| OSLog / Logger | Structured logging with Console.app integration |
| UNUserNotificationCenter | Error/completion notifications |

**External dependency:** ffmpeg (Homebrew install, not bundled). Detected at launch; user prompted if missing.

**Key decision rationale:** No Alamofire (API surface is one endpoint), no TagLib (AVFoundation covers read-only metadata), no OpenAI SDK (URLSession suffices). The only optional SPM package worth considering is `swift-async-algorithms` for debounce/throttle utilities.

**Minimum deployment target:** macOS 14 (Sonoma) recommended — gives access to `@Observable` macro, stable `MenuBarExtra`, and `SMAppService`. macOS 13 is viable if `@Observable` is replaced with `ObservableObject`.

### Expected Features

**MVP (v1) — 13 features:**
- Menu bar icon with on/off/pause controls
- FSEvents folder watcher on ~/Downloads
- Audio pipeline: metadata validation → duration filter → duplicate detection (title+artist) → move to ~/Music → quality ranking → AIFF conversion or low-quality quarantine with CSV log
- PDF pipeline: text extraction → LM Studio classification → move papers to ~/Documents/Papers
- External JSON config at `~/Library/Application Support/OhMyClaw/config.json`
- Menu bar config editing (duration threshold, format cutoff)
- Launch at Login toggle
- ffmpeg availability check at launch
- Error notifications + rotating log file
- macOS permission handling

**Differentiators (what no competitor does):**
- Audio quality ranking with format-aware conversion threshold (configurable cutoff across WAV > FLAC > ALAC > AIFF > MP3 320 > AAC 256 > MP3 128)
- Local LLM-powered PDF classification (novel in file organizer space)
- Metadata-based cross-format duplicate detection
- Low-quality quarantine with transparent CSV manifest

**Anti-features (explicitly out of scope for v1):**
- Recursive subfolder watching (exponential FSEvents load)
- Cloud folder support (placeholder files cause corruption)
- Custom user rules engine (scope creep — this isn't Hazel)
- In-app ffmpeg bundling (~80MB, GPL licensing complexity)
- Natural language rule configuration (LLM is for classification, not config)

**Post-validation additions (v1.x):** Undo/recent activity, dry-run mode, per-task enable/disable, fuzzy duplicate matching, conversion progress indicator, adjustable LLM confidence threshold.

### Architecture Approach

**Pattern:** Protocol-based task system with pipeline processing.

```
MenuBarExtra (SwiftUI)
  └── AppCoordinator (actor, @MainActor, @Observable)
        ├── ConfigStore (JSON load/save/watch)
        ├── FileWatcher (FSEvents + debounce)
        └── TaskRouter → TaskRegistry
              ├── AudioTask (FileTask protocol)
              │     └── Steps: MetadataValidator → DurationChecker → DuplicateDetector
              │                → FileMover → QualityEvaluator → AIFFConverter/LowQualityArchiver
              └── PDFTask (FileTask protocol)
                    └── Steps: ContentExtractor → LLMClassifier → PaperMover
```

**Key architectural decisions:**
1. **`@Observable` + `@MainActor` AppCoordinator** — single source of truth for app state; SwiftUI views re-render automatically
2. **`FileTask` protocol** — `canHandle(file:)` + `process(file:config:)` contract; adding new file types requires zero changes to existing code
3. **`PipelineStep` protocol** — each step is independently testable; pipeline has early exits (missing metadata → skip, too short → skip)
4. **`ConversionPool` actor** — bounded concurrency for ffmpeg via async semaphore pattern, capped at CPU core count
5. **`Process.runAsync()` extension** — bridges `terminationHandler` callback to `async/await` via `CheckedContinuation`
6. **No App Sandbox** — the app accesses ~/Downloads, ~/Music, ~/Documents and spawns ffmpeg; sandboxing would require so many exceptions it negates benefits. Direct distribution (non-App Store).
7. **`LSUIElement = true`** — no dock icon, menu bar only
8. **`.menuBarExtraStyle(.window)`** — popover-style panel for richer config UI (sliders, toggles)

**Project structure:** 8 top-level directories — `App/`, `UI/`, `Config/`, `Core/`, `Tasks/`, `Services/`, `Infrastructure/`, `Tests/`. Each task module (`Audio/`, `PDF/`) contains its own `Steps/` and `Models` for encapsulation.

**State flow:** `MenuBarView` ← `@Observable` → `AppCoordinator` → owns `ConfigStore`, `FileWatcher`, `TaskRouter`. Background work runs on cooperative thread pool. UI reads state directly; UI actions call coordinator methods.

### Critical Pitfalls

**Top 5 (architecture-breaking if not addressed early):**

1. **FSEvents fires before file is fully written** — browsers write downloads progressively; processing incomplete files causes corruption. **Fix:** Ignore temp extensions (`.crdownload`, `.part`), poll file size stability (2 reads 500ms apart with same size), debounce per file path (1–3 seconds).

2. **Zombie ffmpeg processes / pipe deadlocks** — spawning `Process` without draining pipes causes 64KB buffer deadlock; not terminating on app quit creates orphans. **Fix:** Always use `terminationHandler` (not `waitUntilExit`), drain stderr via `readabilityHandler` before `run()`, store all running Process references and `terminate()` on app quit, set per-file timeout (5 min), add `-loglevel warning` to reduce stderr volume.

3. **Menu bar app killed by macOS under memory pressure** — `LSUIElement` apps are low-priority for memory; App Nap throttles them; file watchers silently stop after sleep/wake. **Fix:** `ProcessInfo.disableAutomaticTermination()`, `NSSupportsAutomaticTermination = NO` in Info.plist, re-establish watchers on `NSWorkspace.didWakeNotification`.

4. **LM Studio API brittleness** — LLM may be unavailable, loading a model, OOM, or hallucinating categories. **Fix:** Aggressive timeouts (15s classification, 5s health check), health check on launch with green/red status in menu bar, defensive response parsing (strip markdown fences, validate against category allowlist), fallback rule-based classification, queue requests serially, retry with exponential backoff (max 2), cache results by filename hash.

5. **File move race conditions** — FSEvents delivers multiple events per file operation; user may move/delete file between detection and processing. **Fix:** Track files by inode (not path), check existence before each operation, maintain "currently processing" set, implement idempotent operations, use `NSFileCoordinator` for safe concurrent access, handle `CocoaError.fileNoSuchFile` gracefully.

**Other significant pitfalls:** `.DS_Store`/Spotlight noise in watcher, AVFoundation metadata gaps for non-standard AIFF/WAV, TCC permissions blocking file access, concurrent file operations without isolation, config file corruption (must use `.atomic` writes), DispatchSource file descriptor leaks, ffmpeg PATH differences between Intel/Apple Silicon, AIFF format variant quirks, Swift actor serialization bottleneck on file I/O, notification overload during batch processing.

## Implications for Roadmap

### Phase 0: Project Skeleton
**Rationale:** Establish the macOS app target, menu bar presence, and build infrastructure before any logic. Validates that the SwiftUI `MenuBarExtra` renders correctly with no dock icon.
**Delivers:** Xcode project with SwiftUI lifecycle, `Info.plist` (`LSUIElement = true`), empty `MenuBarExtra` with icon visible in menu bar, SPM configured.
**Estimate:** ~1 day
**Risk:** Low — standard Xcode project setup.

### Phase 1: Configuration System
**Rationale:** Every subsequent module depends on config values (format ranking, duration threshold, ffmpeg path, LM Studio endpoint). Building this first eliminates config-passing uncertainty from all later phases. Addresses Pitfall 13 (atomic writes, validation, fallback to defaults).
**Delivers:** `AppConfig` / `AudioConfig` / `PDFConfig` Codable models, `ConfigStore` with load/save/watch, bundled `default-config.json`, config persisted to `~/Library/Application Support/OhMyClaw/config.json`.
**Estimate:** ~1 day
**Risk:** Low — well-understood Codable + FileManager patterns.

### Phase 2: File Watcher
**Rationale:** The file watcher is the event source for the entire application. Must incorporate debounce and filtering from day one (Pitfalls 1, 2, 10, 16). Getting this wrong means every downstream module inherits unreliable input.
**Delivers:** `FileWatcher` class using FSEvents/DispatchSource, file-size stability debounce (1–2 seconds), temp/hidden file filtering, `AsyncStream`-based event delivery, proper fd cleanup in cancel handler. Wired to `AppCoordinator` start/stop/pause.
**Estimate:** ~1 day
**Risk:** Medium — FSEvents edge cases with sleep/wake (Pitfall 3) need careful testing.

### Phase 3: Task System Core
**Rationale:** The protocol-based task system (`FileTask`, `TaskRegistry`, `TaskRouter`) is the extensibility spine of the app. Building it before any task implementation ensures Audio and PDF modules plug in consistently.
**Delivers:** `FileTask` protocol, `TaskRegistry` with `register()`/`tasks(for:)`, `TaskRouter` dispatching file events to matching tasks. Verified with a dummy task that logs received events.
**Estimate:** ~0.5 day
**Risk:** Low — straightforward protocol + registry pattern.

### Phase 4: Audio Pipeline
**Rationale:** This is the primary use case and primary differentiator. It's also the most complex module with 6 pipeline steps, ffmpeg subprocess management, and concurrency control. Addresses Pitfalls 4, 5, 6, 7, 11, 14, 18, 19.
**Delivers:**
- `MetadataService` (AVFoundation + ffprobe fallback)
- `MetadataValidator`, `DurationChecker`, `DuplicateDetector` (in-memory title+artist index)
- `FileMover` (atomic move to ~/Music)
- `QualityEvaluator` (ranking lookup against config)
- `FFmpegService` (availability check, path detection for Intel/ARM)
- `AIFFConverter` + `ConversionPool` actor (bounded concurrency)
- `CSVLogger` (low-quality manifest)
- `AudioTask` orchestrating all steps
- **End-to-end verification:** Drop audio file in ~/Downloads → appears in ~/Music as AIFF
**Estimate:** ~3 days
**Risk:** High — ffmpeg process management, pipe deadlocks, metadata edge cases, concurrency bugs. Most pitfalls cluster here.

### Phase 5: PDF Pipeline
**Rationale:** Secondary use case but architecturally distinct (network I/O to local LLM vs. subprocess management). Addresses Pitfall 9 (LLM brittleness) as a first-class concern.
**Delivers:**
- `LMStudioClient` (HTTP client with health check, aggressive timeouts, defensive response parsing)
- `ContentExtractor` (PDFKit, first N pages only for memory safety)
- `LLMClassifier` (prompt engineering, confidence threshold, fallback classification)
- `PaperMover` (move to ~/Documents/Papers)
- `PDFTask` orchestrating all steps
- LM Studio status indicator in menu bar (green/red)
- **End-to-end verification:** Drop PDF in ~/Downloads → classified and moved (or left)
**Estimate:** ~1.5 days
**Risk:** Medium — LLM response unpredictability, but contained within one module.

### Phase 6: Menu Bar UI
**Rationale:** With both pipelines functional, the UI wires user controls to the working system. Addresses Pitfall 15 (MenuBarExtra limitations) and Pitfall 20 (notification overload).
**Delivers:**
- `MenuBarView` with on/off/pause toggles, visual state indicators
- `StatusView` showing recent activity feed (last N actions)
- `ConfigEditorView` with duration slider, quality cutoff picker, LM Studio endpoint field
- Batched notifications (summary after debounce window, not per-file)
- Dynamic icon state (idle/processing/error)
**Estimate:** ~1.5 days
**Risk:** Medium — SwiftUI MenuBarExtra quirks across macOS versions; may need NSStatusItem fallback for dynamic icons.

### Phase 7: Polish & Hardening
**Rationale:** Production readiness — the app must survive real-world conditions: sleep/wake cycles, permission revocation, disk full, extended uptime. Addresses Pitfalls 3, 8, 12, 17.
**Delivers:**
- `NotificationManager` with batched error/completion notifications
- Rotating file logger (`~/Library/Logs/OhMyClaw/`)
- `LaunchAtLogin` toggle via `SMAppService`
- ffmpeg availability check at launch with install guidance
- Sleep/wake resilience (re-establish watchers on `didWakeNotification`)
- `ProcessInfo.disableAutomaticTermination()` to prevent macOS killing the app
- Permission error handling with user-facing prompts
- Disk space check before conversion
- App signing and notarization setup
**Estimate:** ~1.5 days
**Risk:** Medium — edge cases are numerous but individually small.

### Phase 8: Testing
**Rationale:** Integration tests validate the full pipeline with real files. Unit tests lock down each step's logic. Mock-based tests verify LLM fault tolerance.
**Delivers:**
- Unit tests for each pipeline step (MetadataValidator, DurationChecker, QualityEvaluator, DuplicateDetector, ConfigStore, TaskRouter)
- Integration tests: full audio pipeline with fixture audio files → verify AIFF output at destination
- Integration tests: PDF pipeline with `URLProtocol` mock for LM Studio → verify classification and move
- Edge case tests: partial downloads, corrupt files, missing metadata, ffmpeg failures, LLM timeouts
- Swift Testing (`@Test`, `#expect`) for parameterized format ranking tests
**Estimate:** ~1 day
**Risk:** Low — testing is well-scoped by this point.

**Total estimated effort: ~11–12 days** for a single developer with Swift/SwiftUI experience.

## Research Confidence

### Well-Understood (HIGH confidence)

- **Stack selection:** All-native Swift/SwiftUI with system frameworks is the clear correct choice. No ambiguity.
- **Menu bar app pattern:** `MenuBarExtra` + `LSUIElement` is well-documented and battle-tested on macOS 13+.
- **FSEvents file watching:** Mature macOS API; debounce and filtering patterns are well-established.
- **ffmpeg integration:** `Foundation.Process` wrapping ffmpeg is a known pattern; the async wrapper with `CheckedContinuation` is standard Swift Concurrency practice.
- **Configuration system:** Codable + JSON + atomic writes to Application Support is idiomatic macOS.
- **Audio metadata reading:** AVFoundation covers the common cases; ffprobe fallback handles edge cases.
- **Project structure:** Protocol-based task system with pipeline steps is well-understood and testable.
- **Pitfalls:** The 20 identified pitfalls are grounded in real macOS development issues with concrete mitigations.

### Moderately Understood (MEDIUM confidence)

- **LM Studio integration reliability:** The API is OpenAI-compatible and straightforward, but real-world behavior (model loading time, response quality, VRAM pressure) hasn't been tested with actual classification prompts. Prompt engineering for paper classification will require iteration.
- **Duplicate detection accuracy:** Title+artist exact matching is clear, but real-world metadata is messy (inconsistent capitalization, diacritics, "feat." variations). Fuzzy matching complexity is deferred to v1.x.
- **macOS version compatibility:** The app targets macOS 14 for `@Observable`, but `MenuBarExtra` behavior differs between macOS 13/14/15. Testing across versions is needed.
- **Concurrency model under load:** The `ConversionPool` actor pattern is sound in theory, but behavior with 20+ simultaneous file arrivals (zip extraction) needs stress testing.

### Uncertain (areas needing validation)

- **ffmpeg auto-install UX:** The spec mentions "auto-install if missing" but Homebrew installation requires user interaction (password, Xcode CLI tools). The actual UX for guiding a non-technical user through ffmpeg installation is unresolved. May need to simplify to "show instructions" rather than true auto-install.
- **LLM classification quality:** Whether a local 7B/13B model can reliably distinguish scientific papers from other PDFs at an acceptable accuracy rate is unvalidated. False positive/negative rates are unknown. A confidence threshold is planned but the right threshold value requires experimentation.
- **Battery/performance impact in production:** Target budgets are set (<1% CPU idle, <50MB RAM idle) but haven't been profiled with real workloads. FSEvents coalescing and ffmpeg CPU impact need measurement.
- **Distribution model:** Non-App Store distribution is assumed (no sandbox), but code signing, notarization, and update mechanism (Sparkle?) aren't fully planned.
- **Sleep/wake reliability:** The mitigations for Pitfall 3 are documented but the interaction between `DispatchSource`, App Nap, and macOS power management during extended laptop sleep is complex and needs real-device testing.
