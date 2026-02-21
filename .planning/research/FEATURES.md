# Feature Research

**Domain:** macOS Menu Bar File Organizer
**Researched:** 2026-02-21
**Confidence:** HIGH

## Competitive Context

Key reference apps in this space:
- **Hazel** (Noodlesoft) — rule-based file automation, macOS native, $42. Gold standard for folder-watching automation.
- **Default Folder X** — file dialog enhancement + folder management.
- **File Juggler** (Windows) — condition/action file organizer.
- **Dropzone** — drag-and-drop file actions from menu bar.
- **SortMyFiles / Declutter** — lightweight auto-organizers by file type.
- **XLD / dBpoweramp** — audio format conversion with metadata awareness.

Oh My Claw differentiates by combining **domain-specific intelligence** (audio quality ranking, LLM-powered PDF classification) with automation — Hazel is general-purpose and rule-driven, not domain-aware.

---

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---|---|---|---|
| **Folder watching (FSEvents)** | Core mechanic of any file organizer; Hazel, Dropzone all do this | Low | Use `DispatchSource.makeFileSystemObjectSource` or `FSEvents` API. Must handle burst arrivals (e.g., downloading a zip that extracts 50 files) |
| **Menu bar icon + controls** | Hazel, Bartender, etc. all live here; users expect lightweight tray presence | Low | SwiftUI `MenuBarExtra` (macOS 13+). Include on/off toggle, pause state indicator |
| **Pause vs. Stop distinction** | Users expect granularity — pause keeps in-flight work, stop is full halt | Low | Already in spec. Expose clearly in UI with visual state change on icon |
| **Launch at login** | Every menu bar app offers this; users consider it broken without it | Low | `SMAppService.mainApp.register()` (macOS 13+) or `ServiceManagement` |
| **Persistent configuration** | Users expect settings to survive restarts | Low | JSON config file. Store in `~/Library/Application Support/OhMyClaw/` not project root |
| **Error notifications** | Users need to know when automation fails silently | Low | `UNUserNotificationCenter` for native macOS notifications |
| **Log file** | Power users debug via logs; required for trust in background automation | Low | Structured log with rotation. `OSLog` + file sink |
| **File type detection by content** | Don't rely solely on extension — renamed files are common in Downloads | Medium | Use UTI (`UTType`) or magic bytes. Critical for audio files that may have wrong extensions |
| **Undo / recent activity view** | Users fear destructive automation; Hazel shows recent actions | Medium | Keep an in-memory or SQLite log of last N actions with source→destination mapping. Undo = move back |
| **Graceful handling of duplicates** | Downloads folder often has `file (1).pdf`, `file (2).pdf` | Low | Detect naming conflicts at destination. Append suffix or skip with notification |
| **Sandboxing / permission prompts** | macOS requires explicit folder access grants | Low | Security-scoped bookmarks for ~/Downloads, ~/Music, ~/Documents. Handle TCC gracefully |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---|---|---|---|
| **Audio quality ranking with format-aware conversion** | No competitor does intelligent "convert only if quality is high enough" — Hazel can't reason about codec quality tiers | Medium | Maintain a ranked list: WAV > FLAC > ALAC > AIFF > MP3 320 > AAC 256 > OGG > MP3 128, etc. Configurable cutoff position. Unique selling point |
| **Parallel ffmpeg conversion** | Batch conversion with concurrency control is expected in pro audio tools but not in file organizers | Medium | Use Swift `TaskGroup` with configurable max concurrency (default: CPU cores / 2). Show progress in menu |
| **LLM-powered PDF classification** | No file organizer uses local AI for content classification; truly novel | High | LM Studio API (OpenAI-compatible endpoint). Must handle: model not running, slow inference, ambiguous results. Confidence threshold needed |
| **Metadata-based duplicate detection** | Matching by title+artist is smarter than filename or hash matching | Medium | Normalize metadata strings (trim, lowercase, remove diacritics) before comparison. Consider Levenshtein distance for fuzzy matching |
| **Low-quality quarantine with CSV manifest** | Transparent handling of rejected files — user can review and decide | Low | CSV with timestamp, original path, format, bitrate, artist, title. Easy to open in Numbers/Excel |
| **Live threshold adjustment from menu bar** | Change duration filter or format cutoff without editing config files | Low | SwiftUI `Slider` or `Stepper` in menu. Write back to JSON config on change |
| **Per-task enable/disable** | Let users turn off PDF classification but keep audio processing on, or vice versa | Low | Task-level toggles in menu. Common in automation apps, missing from lightweight competitors |
| **Dry-run / preview mode** | Show what *would* happen without moving anything. Builds trust in automation | Medium | Log intended actions to notification/UI without executing. Hazel has this; users love it |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---|---|---|---|
| **Recursive subfolder watching** | "Organize everything, not just top-level Downloads" | Exponential FSEvents load, accidental moves of nested project files, permission nightmares | Watch only top-level ~/Downloads. Allow user to add specific additional folders in config |
| **Cloud folder support (iCloud, Dropbox)** | Files often land in cloud-synced folders | Cloud providers use placeholder/evicted files (`.icloud` stubs), triggering false events; moving files mid-sync causes corruption | Document as unsupported in v1. If needed later, wait for download completion before acting |
| **Automatic metadata tagging/correction** | "Fix my mp3 tags automatically" | Metadata correction is a rabbit hole (MusicBrainz, AcoustID). Wrong corrections are worse than no correction | Surface bad/missing metadata in CSV log; let user fix manually. Consider MusicBrainz lookup as v2+ opt-in |
| **Custom user rules engine** | "Let me write my own conditions and actions like Hazel" | Massive scope creep; you're building Hazel. UX for rule editors is hard | Keep domain-specific tasks (audio, PDF) with configurable thresholds. Don't generalize into a rule engine |
| **Watched folder for arbitrary file types** | "Organize my images, videos, code, archives too" | Each file type needs domain-specific logic; generic sorting by extension is commoditized and low-value | Focus v1 on audio + PDF. Add new task modules explicitly, not via generic rules |
| **In-app ffmpeg bundling** | "Don't make me install ffmpeg separately" | Adds ~80MB to app size, licensing complexity (LGPL/GPL), update burden | Check for ffmpeg at launch, prompt install via Homebrew (`brew install ffmpeg`). Provide clear error if missing |
| **Real-time progress bars for conversion** | "Show me percentage complete for each file" | ffmpeg progress parsing is fragile (varies by codec), adds significant UI complexity | Show file count progress (3/10 files converted) rather than per-file percentage. Use `-progress pipe:1` if per-file is demanded later |
| **Natural language rule configuration** | "Use AI to let me describe rules in English" | Adds LLM dependency for config, unpredictable behavior, prompt injection risk | Structured config UI with clear labels. The LLM is for PDF classification, not config |
| **Global hotkeys** | "Toggle with keyboard shortcut" | Conflicts with other apps, accessibility permissions, marginal value for a background service | Expose toggle via menu bar click. If demand is clear, add one configurable hotkey in v1.x |

---

## Feature Dependencies

```
┌─────────────────────────────────────────────────────────┐
│                    Menu Bar Shell                        │
│            (SwiftUI MenuBarExtra, on/off/pause)          │
└────────────┬────────────────────────────┬───────────────┘
             │                            │
             ▼                            ▼
┌────────────────────────┐   ┌────────────────────────────┐
│   Config Manager       │   │   Folder Watcher           │
│   (JSON read/write)    │   │   (FSEvents on ~/Downloads)│
└─────┬──────────────────┘   └─────┬──────────────────────┘
      │                            │
      │  ┌─────────────────────────┤
      │  │                         │
      ▼  ▼                         ▼
┌──────────────┐          ┌──────────────────┐
│ Audio Task   │          │ PDF Task         │
│ Module       │          │ Module           │
└──┬───┬───┬───┘          └──┬───────────────┘
   │   │   │                 │
   ▼   │   ▼                 ▼
┌─────┐│┌──────────┐   ┌─────────────────┐
│Meta ││││ Quality  │   │ LM Studio       │
│Check│││ │ Ranking  │   │ API Client      │
└─────┘│ └──┬───────┘   │ (OpenAI compat) │
       │    │            └─────────────────┘
       ▼    ▼
┌───────────────────┐
│ ffmpeg Converter   │
│ (TaskGroup-based)  │
└───────────────────┘
       │
       ├──► ~/Music (converted AIFF)
       └──► ~/Music/low_quality/ + CSV

Dependencies (build order):
1. Config Manager (no deps)
2. Folder Watcher (depends on: Config Manager)
3. Menu Bar Shell (depends on: Config Manager, Folder Watcher)
4. Audio Metadata Checker (depends on: Config Manager)
5. Quality Ranking Engine (depends on: Config Manager)
6. ffmpeg Converter (depends on: Quality Ranking)
7. Audio Task Module (depends on: 4, 5, 6, Folder Watcher)
8. LM Studio API Client (no deps beyond network)
9. PDF Task Module (depends on: 8, Folder Watcher)
10. Duplicate Detector (depends on: Audio Metadata Checker)
```

---

## MVP Definition

### Launch With (v1)

| Feature | Rationale |
|---|---|
| Menu bar icon with on/off/pause | Core UX shell; everything hangs off this |
| FSEvents folder watcher on ~/Downloads | Core mechanic |
| Audio task: metadata check → duration filter → move to ~/Music | Primary use case from spec |
| Audio task: quality ranking + AIFF conversion via ffmpeg | Primary differentiator |
| Audio task: low_quality folder + CSV log | Spec requirement; builds trust |
| Audio task: duplicate detection by title+artist | Spec requirement; prevents clutter |
| PDF task: LM Studio classification → move papers | Secondary use case from spec |
| External JSON config | Spec requirement |
| Menu bar controls: duration threshold, format cutoff | Spec requirement; live adjustment |
| Launch at login toggle | Table stakes for menu bar apps |
| Error notifications + log file | Table stakes for background automation |
| macOS permission handling (security-scoped bookmarks) | Required for folder access |
| ffmpeg availability check at launch | Fail gracefully if missing |

### Add After Validation (v1.x)

| Feature | Trigger to Build |
|---|---|
| Undo last action / recent activity list | User feedback about accidental moves |
| Dry-run / preview mode | User feedback about trust in automation |
| Per-task enable/disable toggles | Users wanting audio-only or PDF-only mode |
| Configurable watched folders (beyond ~/Downloads) | Repeated user requests for additional sources |
| Fuzzy duplicate matching (Levenshtein on metadata) | Exact match misses near-duplicates |
| Conversion progress indicator (file count) | Users report anxiety during large batch conversions |
| PDF classification confidence threshold (adjustable) | LLM false positives/negatives reported |
| Notification grouping / summary | Too many individual notifications annoy users |

### Future Consideration (v2+)

| Feature | Condition |
|---|---|
| Additional task modules (images, video, archives) | Market demand + clear domain-specific value |
| MusicBrainz metadata lookup (opt-in) | Users request auto-correction despite risks |
| Multiple LLM backend support (Ollama, llama.cpp) | LM Studio proves limiting |
| Shortcuts.app / AppleScript integration | Power users want to trigger from other workflows |
| Statistics dashboard (files processed, space saved) | Engagement/retention feature |
| iCloud/cloud folder support | After solving placeholder file detection |
| Automatic ffmpeg installation prompt (Homebrew) | Too many users fail at manual install |
| Widget for macOS desktop/notification center | macOS widget ecosystem matures |

---

## Key Risks

| Risk | Impact | Mitigation |
|---|---|---|
| LM Studio not running when PDF arrives | PDF task silently fails | Health-check ping on app launch; queue PDFs and retry with backoff; notify user if LM Studio unreachable for >5 min |
| ffmpeg not installed | Audio conversion silently fails | Check at launch, show persistent notification with install instructions. Don't crash — skip conversion, still move files |
| Burst file arrivals (zip extraction) | Watcher floods task queue | Debounce FSEvents (500ms settle time). Process queue serially per task type with concurrency limits |
| macOS permission revocation | App stops working silently | Check bookmark validity on each access attempt. Re-prompt if revoked |
| Large audio files (>1GB) | Conversion blocks for minutes | Show conversion count in menu bar. Use `Task.yield()` to keep UI responsive. Consider file size warning threshold |
| LLM hallucination on PDF classification | Non-papers moved to Papers, or papers ignored | Log classification reasoning. Add confidence score. Let user set threshold. Provide "undo" for recent moves |
