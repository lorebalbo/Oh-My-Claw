# Oh My Claw

A native macOS menu bar app that keeps your Downloads folder clean — automatically.

Drop a music file or a research paper into Downloads and Oh My Claw handles the rest: it validates metadata, converts audio to AIFF if quality is good enough, detects duplicates, and uses the OpenAI API to classify scientific PDFs and route them to the right folder. Everything runs in the background with no Dock presence.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## What It Does

### Audio pipeline
- Watches `~/Downloads` in real-time via FSEvents
- Validates configurable metadata fields (title, artist, album)
- Filters files shorter than a configurable minimum duration (default: 60 s)
- Detects duplicates by matching title + artist against files already in `~/Music`
- Ranks format quality: WAV > FLAC > ALAC > AIFF > MP3 320 > AAC 256 > MP3 128
- Converts qualifying files to AIFF 16-bit via `ffmpeg` (parallel, CPU-core-matched)
- Moves low-quality files to `~/Music/low_quality` and logs them to CSV
- Moves good files to `~/Music`

### PDF pipeline
- Detects PDF files in Downloads
- Extracts text and sends it to the OpenAI API for scientific paper classification
- Moves papers to `~/Documents/Papers`; leaves everything else untouched

### App
- Lives in the menu bar — no Dock icon
- Animated icon while processing; colour-coded for idle / processing / error states
- Pause/resume (in-flight tasks finish before stopping)
- Launch at Login toggle
- Editable config from the menu bar; changes take effect immediately without restart
- Error notifications via macOS Notification Center
- Rotating log file under `~/Library/Logs/OhMyClaw/`

---

## Requirements

- macOS 13 Ventura or later
- `ffmpeg` — checked at launch, guided install if missing (Homebrew)
- OpenAI API key — set `pdf.openaiApiKey` in `config.json` to enable PDF classification (optional; audio pipeline works without it)

---

## Getting Started

1. Clone the repo and open `OhMyClaw.xcodeproj` in Xcode.
2. Build and run (⌘R). The app will appear in the menu bar.
3. On first launch, a default `config.json` is created at:
   ```
   ~/Library/Application Support/OhMyClaw/config.json
   ```
4. Edit the config to set your destinations, quality cutoff, and OpenAI key:
   ```json
   {
     "audio": {
       "destinationPath": "~/Music",
       "qualityCutoff": "mp3_320",
       "minDurationSeconds": 60
     },
     "pdf": {
       "openaiApiKey": "sk-...",
       "openaiModel": "gpt-4o",
       "destinationPath": "~/Documents/Papers"
     }
   }
   ```

---

## Project Status

Functional and in daily use. Core pipelines (audio + PDF) are complete. A few menu bar config-editing features are still in progress (phases 7–9 in the roadmap). Not yet distributed as a signed/notarised app — run from source via Xcode.

---

## Architecture

Modular by design: each file type (audio, PDF) is an independent task that conforms to a shared `FileTask` protocol. Adding support for a new file type means adding a new task module without touching anything else.

```
OhMyClaw/
├── App/          # Coordinator + state
├── Audio/        # Detection, conversion, quality ranking, CSV logging
├── PDF/          # Text extraction, OpenAI classification
├── Config/       # JSON config store + hot-reload watcher
├── Core/         # FSEvents file watcher, FileTask protocol
├── Infrastructure/ # Logger, error collector, notifications
└── UI/           # Menu bar view, icon animator
```
