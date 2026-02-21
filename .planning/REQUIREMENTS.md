# Requirements: Oh My Claw

**Defined:** 2026-02-21
**Core Value:** Audio files with proper metadata and sufficient quality automatically appear in ~/Music as AIFF — no manual sorting, converting, or cleanup required.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Menu Bar & App Lifecycle

- [ ] **APP-01**: User can toggle the app on/off from the menu bar icon
- [ ] **APP-02**: User can pause monitoring from the menu bar (in-flight tasks continue to completion)
- [ ] **APP-03**: User can toggle Launch at Login from the menu bar
- [ ] **APP-04**: Menu bar icon visually indicates app state (idle/processing/error)
- [ ] **APP-05**: Menu bar icon animates while files are being processed

### File Watching

- [ ] **WATCH-01**: App monitors ~/Downloads in real-time using FSEvents
- [ ] **WATCH-02**: Watcher debounces file events to avoid processing incomplete downloads
- [ ] **WATCH-03**: Watcher ignores temporary files (.crdownload, .part, .tmp, .download)

### Audio Pipeline

- [ ] **AUD-01**: App detects audio files in ~/Downloads by file extension and MIME type
- [ ] **AUD-02**: App validates configurable metadata fields (default: title, artist, album) — user can enable/disable each field in config
- [ ] **AUD-03**: App filters audio files by configurable minimum duration (default: 60 seconds)
- [ ] **AUD-04**: App detects duplicate audio files by matching title+artist metadata against existing files in ~/Music (cross-format)
- [ ] **AUD-05**: Duplicate audio files in Downloads are deleted
- [ ] **AUD-06**: Qualifying audio files are moved to ~/Music
- [ ] **AUD-07**: Audio format quality is evaluated against configurable ranking (WAV > FLAC > ALAC > AIFF > MP3 320 > AAC 256 > MP3 128)
- [ ] **AUD-08**: Files at or above the ranking cutoff are converted to AIFF 16-bit via ffmpeg
- [ ] **AUD-09**: Conversions run in parallel matching CPU core count
- [ ] **AUD-10**: Files below the ranking cutoff or not in the ranking are moved to ~/Music/low_quality
- [ ] **AUD-11**: Low-quality file metadata is logged to CSV (Filename, Title, Artist, Album, Format, Bitrate, Date)

### PDF Pipeline

- [ ] **PDF-01**: App detects PDF files in ~/Downloads
- [ ] **PDF-02**: App sends PDF content to LM Studio local API for scientific paper classification
- [ ] **PDF-03**: Classified papers are moved to ~/Documents/Papers
- [ ] **PDF-04**: Non-paper PDFs are left in Downloads untouched

### Configuration

- [ ] **CFG-01**: App reads settings from external JSON config file
- [ ] **CFG-02**: User can edit duration threshold from menu bar
- [ ] **CFG-03**: User can edit format ranking cutoff from menu bar
- [ ] **CFG-04**: User can edit LM Studio port from menu bar
- [ ] **CFG-05**: Config changes take effect immediately without restart

### Infrastructure

- [ ] **INF-01**: App checks for ffmpeg availability at launch and guides user to install if missing
- [ ] **INF-02**: Errors trigger menu bar notification
- [ ] **INF-03**: All operations are logged to rotating log file
- [ ] **INF-04**: App handles macOS sleep/wake by re-establishing file watchers

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
- **INT-03**: LM Studio status indicator (green/red) in menu bar

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
| APP-01 | Pending | Pending |
| APP-02 | Pending | Pending |
| APP-03 | Pending | Pending |
| APP-04 | Pending | Pending |
| APP-05 | Pending | Pending |
| WATCH-01 | Pending | Pending |
| WATCH-02 | Pending | Pending |
| WATCH-03 | Pending | Pending |
| AUD-01 | Pending | Pending |
| AUD-02 | Pending | Pending |
| AUD-03 | Pending | Pending |
| AUD-04 | Pending | Pending |
| AUD-05 | Pending | Pending |
| AUD-06 | Pending | Pending |
| AUD-07 | Pending | Pending |
| AUD-08 | Pending | Pending |
| AUD-09 | Pending | Pending |
| AUD-10 | Pending | Pending |
| AUD-11 | Pending | Pending |
| PDF-01 | Pending | Pending |
| PDF-02 | Pending | Pending |
| PDF-03 | Pending | Pending |
| PDF-04 | Pending | Pending |
| CFG-01 | Pending | Pending |
| CFG-02 | Pending | Pending |
| CFG-03 | Pending | Pending |
| CFG-04 | Pending | Pending |
| CFG-05 | Pending | Pending |
| INF-01 | Pending | Pending |
| INF-02 | Pending | Pending |
| INF-03 | Pending | Pending |
| INF-04 | Pending | Pending |

**Coverage:**
- v1 requirements: 31 total
- Mapped to phases: 0
- Unmapped: 31 ⚠️

---
*Requirements defined: 2026-02-21*
*Last updated: 2026-02-21 after initialization*
