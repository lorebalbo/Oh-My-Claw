# Phase 3: Audio Conversion & Quality - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Evaluate audio quality against the configurable ranking, convert qualifying files to AIFF 16-bit via ffmpeg, quarantine low-quality files to ~/Music/low_quality, log quarantined files to CSV, and manage ffmpeg availability at launch. This phase extends the Phase 2 audio pipeline (detect → validate → deduplicate → move) by inserting quality evaluation and conversion before the final move.

**Requirements:** AUD-07, AUD-08, AUD-09, AUD-10, AUD-11, INF-01

</domain>

<decisions>
## Implementation Decisions

### Quality Evaluation Logic
- **Bitrate mapping:** Lossy formats (MP3, AAC) with bitrates between ranking entries round DOWN to the nearest entry (conservative — if not provably high-quality, treat as lower tier)
- **Cutoff semantics:** Files at or above the cutoff qualify as high quality (inclusive — `qualityCutoff: "mp3_320"` means MP3 320 qualifies for conversion)
- **Unknown formats:** Audio formats not in the ranking list (OGG, WMA, Opus, etc.) are treated as low quality and quarantined
- **Lossless equivalence:** All lossless formats (WAV, FLAC, ALAC, AIFF) are treated equally regardless of bit depth or sample rate — lossless is lossless
- **VBR handling:** Use average bitrate (as reported by AVFoundation) for ranking evaluation
- **AAC threshold:** AAC ≥ 256kbps all rank equal to AAC 256 in the ranking
- **AIFF source files:** Already in target format — skip conversion entirely, just move to ~/Music
- **WAV source files:** Convert to AIFF 16-bit for ~/Music format consistency (even though WAV ranks highest)

### Conversion Lifecycle
- **Original file cleanup:** Delete original from ~/Downloads after successful conversion + move to ~/Music
- **Conversion failure:** Leave original file untouched in ~/Downloads, log the error
- **Partial output protection:** Write ffmpeg output to a temp file (.aiff.tmp), atomic rename on success, delete temp on failure — never leave corrupt .aiff files in ~/Music
- **Pipeline order:** Duplicate check runs BEFORE conversion to avoid wasting CPU on files that will be deleted anyway

### Low-Quality Quarantine & CSV
- **CSV location:** ~/Library/Application Support/OhMyClaw/low_quality_log.csv (with other app data, not co-located with quarantined files)
- **CSV mode:** Append (running log that grows over time, not reset per session)
- **CSV columns:** Filename, Title, Artist, Album, Format, Bitrate, Date
- **Original cleanup:** Delete original from ~/Downloads after moving to ~/Music/low_quality (same as high-quality path)
- **Duplicate handling in low_quality:** If same filename already exists in ~/Music/low_quality, skip the move (don't overwrite, don't suffix)

### ffmpeg Availability
- **Install guidance:** Persistent message in menu bar dropdown when ffmpeg is not found (visible until resolved)
- **Degraded mode:** Without ffmpeg, the audio pipeline still runs (detect, validate metadata, deduplicate, move to ~/Music) but skips the conversion step — files arrive in their original format
- **Check frequency:** Check at launch only; if ffmpeg disappears mid-session, conversion failures are logged as errors
- **Path resolution:** Search known Homebrew paths first (/usr/local/bin/ffmpeg for Intel, /opt/homebrew/bin/ffmpeg for Apple Silicon), then fall back to PATH lookup

### Claude's Discretion
- ffmpeg process arguments and encoding parameters for 16-bit AIFF output
- ConversionPool actor implementation details for CPU-core-bounded parallelism
- CSV formatting specifics (quoting, escaping, date format)
- Error message wording for ffmpeg install guidance
- Temp file naming convention and location

</decisions>

<specifics>
## Specific Ideas

- Quality ranking from requirements: WAV > FLAC > ALAC > AIFF > MP3 320 > AAC 256 > MP3 128
- Config already has `qualityCutoff: "mp3_320"` in default-config.json
- Existing AudioTask pipeline (validate → filter → deduplicate → move) needs conversion step inserted before the final move
- MusicLibraryIndex already handles cross-format duplicate detection by title+artist

</specifics>

<deferred>
## Deferred Ideas

No deferred ideas — all discussion stayed within phase scope.

</deferred>
