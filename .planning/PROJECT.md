# Oh My Claw

## What This Is

A native macOS menu bar application that runs in the background and automatically organizes files from the Downloads folder. It handles audio files (metadata validation, quality-based conversion to AIFF, duplicate detection) and PDF files (scientific paper classification via local LLM). The app is built for a single user — a music-focused power user who wants Downloads to stay clean without manual effort.

## Core Value

Audio files with proper metadata and sufficient quality automatically appear in ~/Music as AIFF — no manual sorting, converting, or cleanup required.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Menu bar presence with on/off/pause controls
- [ ] Real-time file watcher on ~/Downloads
- [ ] Audio file detection and metadata validation (configurable fields, default: title, artist, album)
- [ ] Audio duration filtering (configurable threshold, default: 60s)
- [ ] Move qualifying audio files to ~/Music
- [ ] Audio format quality ranking with configurable cutoff for AIFF conversion
- [ ] Batch AIFF 16-bit conversion via ffmpeg (parallel, matching CPU cores)
- [ ] Duplicate detection by title+artist metadata (cross-format) — delete duplicate from Downloads
- [ ] Low-quality audio files moved to ~/Music/low_quality with CSV logging
- [ ] PDF scientific paper classification via LM Studio local API
- [ ] Move classified papers to ~/Documents/Papers
- [ ] External JSON configuration file
- [ ] Menu bar config editing (duration threshold, format cutoff, etc.)
- [ ] Launch at Login toggle
- [ ] ffmpeg availability check with auto-install if missing
- [ ] Error handling: menu bar notifications + log file
- [ ] Pause stops monitoring but lets in-flight tasks finish

### Out of Scope

- Cloud-based LLM for PDF classification — local only (privacy, no API costs)
- Mobile/iOS companion app — macOS only
- Non-Downloads folder monitoring — v1 watches only ~/Downloads
- Audio streaming/playback — purely file management
- PDF OCR or text extraction beyond LLM classification — simple classify-and-move

## Context

- **Platform**: macOS, Swift/SwiftUI native app
- **Audio conversion**: ffmpeg (external dependency, auto-installed if missing)
- **LLM integration**: LM Studio running locally, OpenAI-compatible API on localhost (default port 1234, configurable)
- **File monitoring**: Real-time file system watcher (FSEvents/DispatchSource)
- **Architecture**: Modular — tasks are independent modules, new tasks can be added over time
- **Audio format ranking** (highest to lowest quality):
  1. WAV
  2. FLAC
  3. ALAC
  4. AIFF
  5. MP3 320kbps
  6. AAC 256kbps
  7. MP3 128kbps
  - Formats not in the ranking → treated as low quality (no conversion, moved to low_quality)
- **CSV columns** for low-quality log: Filename, Title, Artist, Album, Format, Bitrate, Date
- **Concurrency**: ffmpeg conversions run in parallel matching CPU core count
- **Duplicate logic**: Two audio files are duplicates if they share the same title AND artist metadata, regardless of format. The duplicate in Downloads is deleted.

## Constraints

- **Tech stack**: Swift/SwiftUI — native macOS menu bar app
- **Dependencies**: ffmpeg must be available (check + auto-install)
- **LLM**: LM Studio must be running locally for PDF classification to work
- **macOS version**: Target macOS 13+ (Ventura) for modern SwiftUI and menu bar APIs
- **Modularity**: Architecture must support adding new file-type tasks without refactoring existing ones

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift/SwiftUI over Python+rumps | Native performance, proper macOS integration, menu bar API support | — Pending |
| Real-time watcher over polling | Instant response, lower CPU usage than polling | — Pending |
| LM Studio local API over cloud LLM | Privacy, no API costs, works offline | — Pending |
| JSON config over plist/YAML | Human-readable, easy to edit, widely supported tooling | — Pending |
| AIFF 16-bit as target format | DJ/production standard, lossless, broad compatibility | — Pending |
| Duplicate by metadata not filename | Same song in different formats should be caught | — Pending |
| Pause = stop monitoring only | In-flight tasks (conversions, moves) should complete to avoid partial state | — Pending |

---
*Last updated: 2026-02-21 after initialization*
