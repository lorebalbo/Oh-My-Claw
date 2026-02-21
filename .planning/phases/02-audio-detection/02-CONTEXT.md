# Phase 2: Audio Detection & Organization - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Detect audio files in ~/Downloads, validate required metadata, filter by minimum duration, detect duplicates against the existing ~/Music library, and move qualifying files to ~/Music. No audio conversion, no quality ranking, no ffmpeg — those are Phase 3.

</domain>

<decisions>
## Implementation Decisions

### Audio File Detection
- Recognize common formats only: MP3, AAC/M4A, FLAC, WAV, AIFF, ALAC
- Identification requires both file extension AND MIME type to agree (strictest mode)
- Files without an extension are skipped — require a recognized extension
- Non-audio files in ~/Downloads are silently ignored (no log, no notification)

### Metadata Validation Behavior
- Default required fields: title, artist, album (all three must be present)
- Each field is configurable — user can enable/disable in config (per AUD-02)
- Empty string metadata counts as missing — field must have real content
- Trim whitespace and lowercase metadata values before validation
- Files failing validation: leave in ~/Downloads untouched + log the reason at INFO level

### Duplicate Detection Logic
- Match key: title + artist, exact match after normalization (trim + lowercase)
- Scan scope: recursive through all of ~/Music (including subdirectories)
- Cross-format: matching is metadata-based, not filename-based — catches duplicates regardless of format
- When duplicate found: delete the incoming file in ~/Downloads + log the duplicate detection at INFO level
- Index strategy: build an in-memory index of existing ~/Music files at app launch, update incrementally as files are moved

### File Placement in ~/Music
- Flat structure: all qualifying files go directly into ~/Music root (no Artist/Album subfolders)
- Keep original filename — no renaming on move
- Name conflicts (same filename but NOT a metadata duplicate): move incoming file to ~/Music/possible_duplicate/
- Permission errors: prompt user for access via macOS dialog if app lacks write permission to ~/Music

### Claude's Discretion
- Specific audio MIME type mappings for each format
- AVFoundation vs other framework choice for metadata reading
- In-memory index data structure and update strategy
- Duration comparison precision (seconds vs milliseconds)
- Internal pipeline architecture (how detection → validation → duplicate check → move is wired)

</decisions>

<specifics>
## Specific Ideas

- Metadata normalization is key: trim + lowercase before any comparison (validation or duplicate matching)
- The in-memory index should be ready before the watcher starts delivering files — build it during app launch
- Possible duplicate folder (~/Music/possible_duplicate) handles the edge case of same filename but different content — don't lose files

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-audio-detection*
*Context gathered: 2026-02-21*
