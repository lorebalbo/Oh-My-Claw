# Requirements: Oh My Claw

**Defined:** 2026-02-21
**Core Value:** Audio files with proper metadata and sufficient quality automatically appear in ~/Music as AIFF — no manual sorting, converting, or cleanup required.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Menu Bar & App Lifecycle

- [x] **APP-01**: User can toggle the app on/off from the menu bar icon
- [ ] **APP-02**: User can pause monitoring from the menu bar (in-flight tasks continue to completion)
- [ ] **APP-03**: User can toggle Launch at Login from the menu bar
- [ ] **APP-04**: Menu bar icon visually indicates app state (idle/processing/error)
- [ ] **APP-05**: Menu bar icon animates while files are being processed

### File Watching

- [x] **WATCH-01**: App monitors ~/Downloads in real-time using FSEvents
- [x] **WATCH-02**: Watcher debounces file events to avoid processing incomplete downloads
- [x] **WATCH-03**: Watcher ignores temporary files (.crdownload, .part, .tmp, .download)

### Audio Pipeline

- [x] **AUD-01**: App detects audio files in ~/Downloads by file extension and MIME type
- [x] **AUD-02**: App validates configurable metadata fields (default: title, artist, album) — user can enable/disable each field in config
- [x] **AUD-03**: App filters audio files by configurable minimum duration (default: 60 seconds)
- [x] **AUD-04**: App detects duplicate audio files by matching title+artist metadata against existing files in ~/Music (cross-format)
- [x] **AUD-05**: Duplicate audio files in Downloads are deleted
- [x] **AUD-06**: Qualifying audio files are moved to ~/Music
- [x] **AUD-07**: Audio format quality is evaluated against configurable ranking (WAV > FLAC > ALAC > AIFF > MP3 320 > AAC 256 > MP3 128)
- [x] **AUD-08**: Files at or above the ranking cutoff are converted to AIFF 16-bit via ffmpeg
- [x] **AUD-09**: Conversions run in parallel matching CPU core count
- [x] **AUD-10**: Files below the ranking cutoff or not in the ranking are moved to ~/Music/low_quality
- [x] **AUD-11**: Low-quality file metadata is logged to CSV (Filename, Title, Artist, Album, Format, Bitrate, Date)

### PDF Pipeline

- [x] **PDF-01**: App detects PDF files in ~/Downloads
- [x] **PDF-02**: App sends PDF content to OpenAI API for scientific paper classification
- [x] **PDF-03**: Classified papers are moved to ~/Documents/Papers
- [x] **PDF-04**: Non-paper PDFs are left in Downloads untouched

### Configuration

- [x] **CFG-01**: App reads settings from external JSON config file
- [ ] **CFG-02**: User can edit duration threshold from menu bar
- [ ] **CFG-03**: User can edit format ranking cutoff from menu bar
- [ ] **CFG-04**: User can edit OpenAI model from menu bar
- [x] **CFG-05**: Config changes take effect immediately without restart

### Infrastructure

- [x] **INF-01**: App checks for ffmpeg availability at launch and guides user to install if missing
- [x] **INF-02**: Errors trigger menu bar notification
- [x] **INF-03**: All operations are logged to rotating log file
- [x] **INF-04**: App handles macOS sleep/wake by re-establishing file watchers

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### User Experience

- **UX-01**: Recent activity feed showing last N actions in menu bar dropdown
- **UX-02**: Dry-run mode to preview actions without executing them
- **UX-03**: Per-task enable/disable toggles (pause audio or PDF independently)
- **UX-04**: Conversion progress indicator in menu bar

### Intelligence

- **INT-01**: Fuzzy duplicate matching (handle inconsistent capitalization, diacritics, "feat." variations)
- **INT-02**: Adjustable LLM confidence threshold for paper classification
- **INT-03**: OpenAI API key status indicator (green/red) in menu bar

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Cloud folder monitoring (iCloud, Dropbox) | Placeholder files break file detection; exponential complexity |
| Custom user rules engine | Scope creep — this isn't Hazel; domain-specific logic is hardcoded |
| Bundled ffmpeg binary | ~80MB size, GPL licensing complexity; require Homebrew install instead |
| Recursive subfolder watching | Exponential FSEvents load; v1 monitors ~/Downloads root only |
| Mobile/iOS companion app | macOS only; no cross-platform requirement |
| Audio streaming/playback | Purely file management, not a media player |
| Natural language rule configuration | LLM is for classification, not config authoring |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| APP-01 | Phase 1 | Not started |
| APP-02 | Phase 5 | Not started |
| APP-03 | Phase 5 | Not started |
| APP-04 | Phase 5 | Not started |
| APP-05 | Phase 5 | Not started |
| WATCH-01 | Phase 1 | Not started |
| WATCH-02 | Phase 1 | Not started |
| WATCH-03 | Phase 1 | Not started |
| AUD-01 | Phase 2 | Complete |
| AUD-02 | Phase 2 | Complete |
| AUD-03 | Phase 2 | Complete |
| AUD-04 | Phase 2 | Complete |
| AUD-05 | Phase 2 | Complete |
| AUD-06 | Phase 2 | Complete |
| AUD-07 | Phase 3 | Not started |
| AUD-08 | Phase 3 | Not started |
| AUD-09 | Phase 3 | Not started |
| AUD-10 | Phase 3 | Not started |
| AUD-11 | Phase 3 | Not started |
| PDF-01 | Phase 4 | Complete |
| PDF-02 | Phase 4 | Complete |
| PDF-03 | Phase 4 | Complete |
| PDF-04 | Phase 4 | Complete |
| CFG-01 | Phase 1 | Not started |
| CFG-02 | Phase 5 | Not started |
| CFG-03 | Phase 5 | Not started |
| CFG-04 | Phase 5 | Not started |
| CFG-05 | Phase 6 | Not started |
| INF-01 | Phase 3 | Not started |
| INF-02 | Phase 6 | Not started |
| INF-03 | Phase 1 | Not started |
| INF-04 | Phase 6 | Not started |

**Coverage:**
- v1 requirements: 32 total
- Mapped to phases: 32 ✅
- Unmapped: 0

| Phase | Requirements | Count |
|-------|-------------|-------|
| Phase 1 | APP-01, WATCH-01, WATCH-02, WATCH-03, CFG-01, INF-03 | 6 |
| Phase 2 | AUD-01, AUD-02, AUD-03, AUD-04, AUD-05, AUD-06 | 6 |
| Phase 3 | AUD-07, AUD-08, AUD-09, AUD-10, AUD-11, INF-01 | 6 |
| Phase 4 | PDF-01, PDF-02, PDF-03, PDF-04 | 4 |
| Phase 5 | APP-02, APP-03, APP-04, APP-05, CFG-02, CFG-03, CFG-04 | 7 |
| Phase 6 | CFG-05, INF-02, INF-04 | 3 |
| **Total** | | **32** |

---
*Requirements defined: 2026-02-21*
*Last updated: 2026-02-21 — Traceability mapped to roadmap phases*
