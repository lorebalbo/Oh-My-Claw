# Roadmap: Oh My Claw

## Overview

Oh My Claw is delivered in 6 sequential phases following natural dependency boundaries: foundation first (app shell, file watcher, config, logging), then the primary audio pipeline split into detection/organization and conversion/quality, followed by the secondary PDF classification pipeline, then the full menu bar UI and controls, and finally production hardening. Each phase produces a vertically integrated slice that can be verified end-to-end before proceeding. All 32 v1 requirements are mapped exactly once.

## Phases
- [x] **Phase 1: App Foundation & File Watching** — Menu bar app shell, FSEvents watcher, config system, and logging (completed 2026-02-21)
- [x] **Phase 2: Audio Detection & Organization** — Detect audio files, validate metadata, filter by duration, handle duplicates, and move to ~/Music (completed 2026-02-22)
- [x] **Phase 3: Audio Conversion & Quality** — Quality ranking, AIFF conversion via ffmpeg, low-quality quarantine, and CSV logging (completed 2026-02-22)
- [x] **Phase 4: PDF Classification** — LLM-powered scientific paper detection and routing via OpenAI API (completed 2026-02-22)
- [ ] **Phase 5: Menu Bar Controls & Configuration** — State indicators, animations, pause/resume, Launch at Login, and in-app config editing
- [ ] **Phase 6: Resilience & Polish** — Error notifications, config hot-reload, and sleep/wake recovery

## Phase Details

### Phase 1: App Foundation & File Watching
**Goal**: Establish the menu bar app, real-time file monitoring, configuration infrastructure, and structured logging — the foundation everything else builds on.
**Depends on**: Nothing (first phase)
**Requirements**: APP-01, WATCH-01, WATCH-02, WATCH-03, CFG-01, INF-03
**Success Criteria** (what must be TRUE):
  1. App appears as a menu bar icon with no Dock presence; clicking the icon reveals a dropdown where the user can toggle monitoring on/off
  2. Dropping a file in ~/Downloads produces a timestamped log entry within 5 seconds (debounce + stability check)
  3. Temporary/partial download files (.crdownload, .part, .tmp, .download) are never logged or processed
  4. config.json is created with defaults at ~/Library/Application Support/OhMyClaw/ on first launch and settings are read from it on subsequent launches

Plans:
- [x] 01-01: Xcode project scaffold with MenuBarExtra, LSUIElement, and SPM configuration
- [x] 01-02: Configuration system — ConfigStore with JSON model, bundled defaults, and Application Support persistence
- [x] 01-03: FSEvents file watcher with debounce and temp file filtering
- [x] 01-04: Logging infrastructure with rotating log file and on/off toggle wiring

---

### Phase 2: Audio Detection & Organization
**Goal**: Deliver the core audio value — files with proper metadata and sufficient duration are automatically moved to ~/Music, duplicates are caught and deleted.
**Depends on**: Phase 1 (file watcher, config, logging)
**Requirements**: AUD-01, AUD-02, AUD-03, AUD-04, AUD-05, AUD-06
**Success Criteria** (what must be TRUE):
  1. An audio file with complete required metadata (title, artist, album) and duration ≥60s dropped in ~/Downloads is automatically moved to ~/Music
  2. An audio file missing any required metadata field remains in ~/Downloads untouched
  3. An audio file shorter than the configured duration threshold remains in ~/Downloads untouched
  4. When a file with the same title+artist already exists in ~/Music (regardless of format), the incoming duplicate in ~/Downloads is deleted

Plans:
- [x] 02-01: Audio file identification (UTType) and metadata reading (AVFoundation async API)
- [x] 02-02: Music library index actor, AudioTask pipeline (validate → filter → deduplicate → move)
- [x] 02-03: AppCoordinator integration (index build, event routing) and unit tests

---

### Phase 3: Audio Conversion & Quality
**Goal**: Evaluate audio quality against the configurable ranking, convert qualifying files to AIFF 16-bit via ffmpeg, quarantine low-quality files, and manage ffmpeg availability.
**Depends on**: Phase 2 (audio detection and move pipeline)
**Requirements**: AUD-07, AUD-08, AUD-09, AUD-10, AUD-11, INF-01
**Success Criteria** (what must be TRUE):
  1. Audio files ranked at or above the quality cutoff appear in ~/Music as converted .aiff files (16-bit)
  2. Audio files ranked below the cutoff or not in the quality ranking appear in ~/Music/low_quality in their original format
  3. Each low-quality file produces a CSV log entry with columns: Filename, Title, Artist, Album, Format, Bitrate, Date
  4. Dropping 8+ qualifying files simultaneously results in parallel ffmpeg conversions capped at CPU core count
  5. If ffmpeg is not installed, the app displays install guidance at launch instead of silently failing

Plans:
- [x] 03-01: ffmpeg service & conversion pool — FFmpegLocator path detection, FFmpegConverter async Process wrapper, ConversionPool actor
- [x] 03-02: Quality models & metadata extension — QualityTier/AudioFormat enums, tier resolution, AudioMetadata format+bitrate via AVFoundation
- [x] 03-03: Audio pipeline integration — CSVWriter, AudioTask quality branching, AppCoordinator ffmpeg wiring, MenuBarView guidance, unit tests

---

### Phase 4: PDF Classification
**Goal**: Classify PDF files as scientific papers using the OpenAI API (GPT-4o) and route them to ~/Documents/Papers; leave non-papers untouched.
**Depends on**: Phase 1 (file watcher, config, logging)
**Requirements**: PDF-01, PDF-02, PDF-03, PDF-04
**Success Criteria** (what must be TRUE):
  1. A scientific paper PDF dropped in ~/Downloads is classified and moved to ~/Documents/Papers
  2. A non-paper PDF (invoice, receipt, manual) dropped in ~/Downloads remains untouched in ~/Downloads
  3. When the OpenAI API key is not configured or API calls fail, PDFs remain in ~/Downloads and the failure is logged

Plans:
- [x] 04-01: PDF detection and text extraction via PDFKit (completed 2026-02-22)
- [x] 04-02: OpenAI HTTP client, classification prompt, and paper routing logic (completed 2026-02-22)
- [x] 04-03: Gap closure — all gaps confirmed resolved in 04-02 (completed 2026-02-22)

---

### Phase 5: Menu Bar Controls & Configuration
**Goal**: Full menu bar UI with dynamic state indicators, icon animation, pause/resume, Launch at Login, and in-app settings editing.
**Depends on**: Phase 2, Phase 3, Phase 4 (working pipelines to display state for)
**Requirements**: APP-02, APP-03, APP-04, APP-05, CFG-02, CFG-03, CFG-04
**Success Criteria** (what must be TRUE):
  1. Menu bar icon visually changes to reflect app state: idle, processing, or error
  2. Menu bar icon animates while files are actively being processed
  3. Pausing from the menu bar stops new file detection while in-flight tasks (conversions, moves) complete
  4. Launch at Login toggle persists across app restarts
  5. User can edit duration threshold, format quality cutoff, and OpenAI model from the menu bar dropdown

Plans:
- [ ] 05-01: Dynamic menu bar icon with state visualization and processing animation
- [ ] 05-02: Pause/resume and Launch at Login lifecycle controls
- [ ] 05-03: Configuration editor UI (duration slider, quality cutoff picker, LM Studio port field)

---

### Phase 6: Resilience & Polish
**Goal**: Production hardening — error notifications, live config reload from any source, and system event resilience.
**Depends on**: Phase 5 (all features in place to harden)
**Requirements**: CFG-05, INF-02, INF-04
**Success Criteria** (what must be TRUE):
  1. Processing errors trigger a macOS notification visible in Notification Center
  2. After macOS wakes from sleep, file monitoring resumes and new files in ~/Downloads are detected
  3. Config changes — whether from the menu bar UI or an external text editor — take effect immediately without app restart

Plans:
- [ ] 06-01: Error notification system with batching to prevent notification spam
- [ ] 06-02: Config file watcher for hot-reload and sleep/wake recovery for FSEvents

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|---------------|--------|-----------|
| 1. App Foundation & File Watching | 4/4 | Complete    | 2026-02-21 |
| 2. Audio Detection & Organization | 3/3 | Complete    | 2026-02-22 |
| 3. Audio Conversion & Quality | 3/3 | Complete    | 2026-02-22 |
| 4. PDF Classification | 3/3 | Complete    | 2026-02-22 |
| 5. Menu Bar Controls & Configuration | 0/3 | Not started | - |
| 6. Resilience & Polish | 0/2 | Not started | - |

**Total plans: 13/18 complete**

---
*Roadmap created: 2026-02-21*
*Last updated: 2026-02-22 — Plan 04-03 gap closure complete (all Phase 04 gaps confirmed resolved)*
