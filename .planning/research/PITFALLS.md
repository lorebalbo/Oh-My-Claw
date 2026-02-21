# Pitfalls Research

**Domain:** macOS Menu Bar File Organizer (Swift/SwiftUI)
**Researched:** 2026-02-21
**Confidence:** HIGH

---

## Critical Pitfalls

### Pitfall 1: FSEvents Fires Before File Is Fully Written

**What goes wrong:** FSEvents (via `DispatchSource.makeFileSystemObjectSource` or `FileManager` monitoring) fires a notification the instant a file *appears* in ~/Downloads — but the file is still being written by Safari, Chrome, or AirDrop. Reading metadata or moving the file at this point causes truncation, corruption, or "file in use" errors.

**Why it happens:** macOS browsers write downloads in stages: (1) create a `.crdownload` / `.download` / `.part` temp file, (2) write data, (3) rename to final name. FSEvents fires on each stage. Even after the final rename, the file descriptor may still be held open and quarantine xattrs are still being applied.

**How to avoid:**
- Ignore files with temp extensions (`.crdownload`, `.part`, `.download`, `.tmp`)
- Ignore files prefixed with `.` (hidden partial files)
- After detecting a new file, poll until the file size stabilizes (e.g., 2 consecutive reads 500ms apart with same size) AND `fcntl(fd, F_GETLK)` shows no write locks
- Use a debounce timer per file path (1–3 seconds) — reset the timer on every new event for that path
- Check `com.apple.quarantine` xattr existence as a "download complete" heuristic (Safari sets it at the end)

**Warning signs:** Corrupted audio files, truncated PDFs, "file not found" errors when file was just detected, intermittent failures on large downloads.

**Phase to address:** Architecture — this must be baked into the file watcher from day one.

---

### Pitfall 2: `.DS_Store` and Spotlight Metadata Noise

**What goes wrong:** Monitoring ~/Downloads triggers events for `.DS_Store`, `.localized`, Spotlight `.metadata_never_index`, and Finder preview cache files. Processing these wastes CPU and can trigger infinite loops if your organizer writes to the same directory it monitors.

**Why it happens:** macOS generates filesystem metadata constantly. If you move a file into a subdirectory of ~/Downloads, Finder updates `.DS_Store` in both source and destination, triggering more events.

**How to avoid:**
- Maintain an explicit allowlist of file extensions to process (`.aif`, `.aiff`, `.wav`, `.mp3`, `.flac`, `.pdf`, etc.)
- Ignore all dotfiles (names starting with `.`)
- If organizing into subdirectories of ~/Downloads, use `DispatchSource` flags carefully or exclude known subdirectory paths
- Never write organizer state/config files into the watched directory

**Warning signs:** High CPU usage when idle, log spam, infinite event loops.

**Phase to address:** Implementation of file watcher.

---

### Pitfall 3: Menu Bar App Vanishes After macOS Nap / Memory Pressure

**What goes wrong:** A menu bar–only app (LSUIElement or `App` with no window) can be killed by macOS under memory pressure because it has no visible UI. The `NSStatusItem` disappears. Additionally, after system sleep/wake, the status bar icon may not redraw or the app may lose its file watcher.

**Why it happens:** macOS treats background-only apps as low-priority for memory. `App Nap` throttles apps with no visible windows. The system can also purge the `NSStatusItem` if the status bar overflows.

**How to avoid:**
- Set `ProcessInfo.processInfo.automaticTerminationSupportEnabled = false` to prevent macOS from auto-terminating
- Call `ProcessInfo.processInfo.disableAutomaticTermination("File watcher active")` while processing
- Disable App Nap: `ProcessInfo.processInfo.disableSuddenTermination()`
  or add `NSSupportsAutomaticTermination = NO` to Info.plist
- Re-create `NSStatusItem` in `applicationDidBecomeActive` / `NSWorkspace.didWakeNotification` as a safety net
- Re-establish file watchers after wake events — `DispatchSource` file monitors can silently stop after sleep

**Warning signs:** Users report the menu bar icon "disappearing," file watcher stops working after laptop lid close/open.

**Phase to address:** Architecture — lifecycle management must be designed upfront.

---

### Pitfall 4: Zombie ffmpeg Processes / Resource Leaks

**What goes wrong:** Spawning ffmpeg via `Process` (née `NSTask`) and not properly waiting for termination or handling errors creates zombie processes. If the user quits the app mid-conversion, orphaned ffmpeg processes continue consuming CPU and may hold file locks.

**Why it happens:** `Process.launch()` / `Process.run()` forks a child process. If you don't call `waitUntilExit()` (or use `terminationHandler`) and the parent exits, the child becomes orphaned. If you use `waitUntilExit()` on the main thread, you block the UI. Pipes that aren't drained can cause ffmpeg to block on write and hang forever.

**How to avoid:**
- Always use `terminationHandler` rather than `waitUntilExit()` for async execution
- Store references to all running `Process` objects; on app quit (`applicationWillTerminate`), call `terminate()` then `waitUntilExit()` on each
- Use process groups: set `process.qualityOfService = .userInitiated` and track PIDs
- Drain both `standardOutput` and `standardError` pipes — ffmpeg writes heavily to stderr. Use `readabilityHandler` on the `FileHandle` to drain asynchronously
- Set a timeout (e.g., 5 minutes per file) using `DispatchWorkItem` and kill the process if exceeded
- Use `Process.isRunning` checks before force-killing

```swift
// Anti-pattern: blocks main thread, leaks on timeout
process.waitUntilExit()

// Correct pattern:
process.terminationHandler = { proc in
    // Handle completion on background queue
}
// AND drain pipes:
errPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    // accumulate or discard
}
```

**Warning signs:** Activity Monitor shows multiple ffmpeg processes after app quits, "too many open files" errors, fans spinning with app "idle."

**Phase to address:** Core implementation of audio processing module.

---

### Pitfall 5: Pipe Deadlock with Process I/O

**What goes wrong:** When using `Pipe()` for `standardOutput` and `standardError` on a `Process`, the internal pipe buffer (typically 64KB on macOS) fills up. If ffmpeg writes more than 64KB to stderr (common with verbose output or long conversions), it blocks waiting for the buffer to drain. If your code calls `waitUntilExit()` before reading the pipes, you deadlock.

**Why it happens:** POSIX pipes have finite buffers. `waitUntilExit()` waits for the process to end, but the process is blocked on pipe write. Classic producer-consumer deadlock.

**How to avoid:**
- Always set up `readabilityHandler` on pipe file handles *before* calling `process.run()`
- Alternatively, read pipes on separate threads using `readDataToEndOfFile()` on background queues, then call `waitUntilExit()`
- For ffmpeg specifically, add `-loglevel warning` or `-loglevel error` to reduce stderr output volume
- Consider using `/dev/null` for stdout if you don't need it: `process.standardOutput = FileHandle.nullDevice`

**Warning signs:** Conversions hang indefinitely on large files, app freezes when processing.

**Phase to address:** Audio processing implementation.

---

### Pitfall 6: Concurrent File Operations Without Proper Isolation

**What goes wrong:** Processing multiple files in parallel (e.g., converting 5 AIFF files simultaneously) without limiting concurrency. Each ffmpeg instance consumes significant RAM (especially for large audio files) and CPU. macOS may throttle or kill the app. Additionally, moving files concurrently to the same destination without atomicity can cause overwrites.

**Why it happens:** Naive use of `DispatchQueue.global().async` or `TaskGroup` without concurrency limits. Each task is independent but competes for disk I/O, CPU, and memory.

**How to avoid:**
- Use an `OperationQueue` with `maxConcurrentOperationCount` set to 2–4 (or `ProcessInfo.processInfo.activeProcessorCount - 1`)
- For Swift Concurrency, use a custom `AsyncStream`-based semaphore or a bounded `TaskGroup`
- Use `FileManager.default.moveItem(at:to:)` which is atomic on the same volume (APFS)
- Generate unique destination filenames before moving (append UUID or timestamp if conflict)
- Use a serial `DispatchQueue` for all file move/rename operations to prevent races

**Warning signs:** System slowdown during batch processing, files overwritten or "lost," random conversion failures.

**Phase to address:** Architecture — concurrency model must be designed before implementation.

---

### Pitfall 7: Audio Metadata Reading Failures (AVFoundation / CoreAudio Edge Cases)

**What goes wrong:** Using `AVAsset` or `AVAudioFile` to read metadata fails silently or returns nil for certain audio formats. AIFF files with non-standard chunks, WAV files with BWF extensions, or MP3 files with APE tags (instead of ID3) return empty metadata. Files downloaded from the internet may have incorrect file extensions.

**Why it happens:** Apple's AVFoundation has incomplete support for some metadata formats. It favors iTunes-style metadata (MP4/M4A) and basic ID3. AIFF metadata is stored in custom chunks that AVFoundation may not parse. Format detection by extension is unreliable.

**How to avoid:**
- Detect format by reading file magic bytes, not extension:
  - AIFF: `FORM....AIFF`
  - WAV: `RIFF....WAVE`
  - MP3: `ID3` or `0xFF 0xFB` sync bytes
  - FLAC: `fLaC`
- Fall back to ffprobe (`ffprobe -v quiet -print_format json -show_format -show_streams`) for metadata — it handles far more formats than AVFoundation
- Handle nil/empty metadata gracefully — always have a fallback classification path
- Be aware that `AVAsset.loadMetadata(for:)` is async in modern APIs and can throw

**Warning signs:** Files classified as "unknown," metadata fields sporadically nil, works for some audio files but not others of the same "format."

**Phase to address:** Audio processing implementation.

---

### Pitfall 8: macOS Sandbox and TCC Permissions Blocking File Access

**What goes wrong:** The app can't read ~/Downloads or can't execute ffmpeg. File operations fail with "Operation not permitted" or "permission denied." After a clean install or macOS update, previously granted permissions are revoked.

**Why it happens:** macOS TCC (Transparency, Consent, and Control) restricts access to user directories. If distributed via App Store, sandboxing is mandatory and ~/Downloads access requires a specific entitlement. Even outside the sandbox, Full Disk Access may be needed. Executing bundled binaries (ffmpeg) requires proper code signing.

**How to avoid:**
- For direct distribution (non-App Store):
  - Request `com.apple.security.files.user-selected.read-write` at minimum
  - If not sandboxed, ~/Downloads is accessible but document this for users
  - Sign ffmpeg binary with your Developer ID or use `--deep` signing on the app bundle
- For App Store:
  - Use `com.apple.security.files.downloads.read-write` entitlement for ~/Downloads
  - ffmpeg cannot be bundled in a sandboxed app (it's a command-line tool); use AVFoundation or AudioToolbox instead
  - Use Security-Scoped Bookmarks for persistent access to user-chosen directories
- Always check `FileManager.default.isReadableFile(atPath:)` before operations
- Handle permission errors gracefully with user-facing prompts
- Request Accessibility/Automation permissions only if needed (don't over-request)

**Warning signs:** Works in Xcode debug but fails when archived/distributed, works on dev machine but fails on clean install, "Operation not permitted" in Console.app.

**Phase to address:** Project setup — entitlements and signing must be configured first.

---

### Pitfall 9: LLM API (LM Studio) Integration Brittleness

**What goes wrong:** The local LLM API is unavailable (LM Studio not running), responds slowly (30+ seconds for classification), returns malformed JSON, hallucinates categories, or runs out of VRAM mid-request. The app hangs or crashes waiting for classification.

**Why it happens:** Local LLM inference is resource-intensive and unpredictable. LM Studio may not auto-start, may be loading a model, or may OOM. The LLM response format isn't guaranteed — it may include markdown formatting, extra text, or invalid JSON even when instructed to return JSON.

**How to avoid:**
- Implement aggressive timeouts: 10–15 seconds for classification, 5 seconds for health check
- Health check LM Studio on app launch (`GET /v1/models`) — show status in menu bar (green/red dot)
- Parse LLM responses defensively:
  - Strip markdown code fences (```json ... ```)
  - Try multiple JSON extraction strategies (full response, regex for `{...}`, line-by-line)
  - Validate extracted categories against a known allowlist
- Implement fallback classification (rule-based, by filename/keywords) when LLM is unavailable
- Queue PDF classification requests — don't fire 20 simultaneous requests to a local LLM
- Implement retry with exponential backoff (max 2 retries)
- Cache classification results (filename hash → category) to avoid re-classifying on restart
- Use streaming responses if supported to detect early failures

```swift
// Anti-pattern: no timeout, no error handling
let (data, _) = try await URLSession.shared.data(from: llmURL)

// Correct pattern:
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 15
config.timeoutIntervalForResource = 30
let session = URLSession(configuration: config)
```

**Warning signs:** App hangs when LM Studio is loading a model, classifications are wrong or random, "connection refused" errors, app becomes unusable without LLM.

**Phase to address:** Architecture — LLM must be treated as an unreliable external dependency.

---

### Pitfall 10: File Move Race Conditions (Watcher vs. Processor)

**What goes wrong:** The file watcher detects a new file and enqueues it for processing. Before processing completes, the user moves/deletes the file manually, or another event fires for the same file (rename, xattr change). The processor tries to access a file that no longer exists or has a different path, causing crashes or duplicate processing.

**Why it happens:** FSEvents delivers multiple events per file operation (create, modify, rename, xattr change). There's no atomic "file download complete" event. Time gap between detection and processing is a race window.

**How to avoid:**
- Track files by inode (`stat().st_ino` or `URL.resourceValues(forKeys: [.fileResourceIdentifierKey])`) rather than path — inodes survive renames
- Check file existence immediately before each operation (`FileManager.default.fileExists(atPath:)`)
- Use an in-memory set of "currently processing" file identifiers to prevent duplicate processing
- Implement idempotent operations — if a file was already moved, detect and skip gracefully
- Use `coordinateReadingItem(at:)` / `coordinateWritingItem(at:)` (NSFileCoordinator) for safe concurrent access with Finder and other apps
- Wrap file operations in do/catch and handle `CocoaError.fileNoSuchFile` / `CocoaError.fileWriteFileExists` specifically

**Warning signs:** "File not found" errors in logs, files processed twice, files disappearing from destination.

**Phase to address:** Architecture — core file processing pipeline design.

---

### Pitfall 11: Large File Handling (Memory Spikes and Disk I/O)

**What goes wrong:** Loading entire audio files into memory for metadata reading or processing. A single WAV/AIFF file can be 500MB–2GB (recording sessions). The app's memory footprint spikes, macOS may kill it, or the system becomes unresponsive.

**Why it happens:** Naive use of `Data(contentsOf: url)` to read files, or AVFoundation loading entire files for metadata extraction. ffmpeg conversion of large files generates large temporary files.

**How to avoid:**
- Never read entire audio files into memory — use `FileHandle` for header-only reads (first 4KB is enough for format detection and basic metadata)
- Use ffprobe for metadata (it reads only headers)
- For ffmpeg conversions, ensure output goes directly to the destination path (no temp file + move pattern unless necessary)
- Monitor available disk space before conversion: `URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])`
- Use `Process` (not in-memory) for ffmpeg — the conversion happens out-of-process
- Implement file size limits (e.g., skip files > 4GB) with user notification
- For PDF classification, extract text without loading the full PDF into memory — use `PDFDocument` page-by-page or just the first few pages

**Warning signs:** Memory usage spikes to GB range, app killed by jetsam (check Console.app for `EXC_RESOURCE`), spinning beachball during large file processing.

**Phase to address:** Implementation of audio and PDF processing.

---

### Pitfall 12: Launch at Login Implementation Gotchas

**What goes wrong:** The "Launch at Login" feature uses the wrong API, doesn't work after app is moved, or creates duplicate instances. On modern macOS, the old `SMLoginItemSetEnabled` approach with helper apps is deprecated but the new `SMAppService` has its own quirks.

**Why it happens:** Apple has changed the Launch at Login API multiple times (Login Items, SMLoginItemSetEnabled with helper bundle, ServiceManagement framework, SMAppService in macOS 13+). Each approach has different requirements and failure modes.

**How to avoid:**
- macOS 13+ (Ventura): Use `SMAppService.mainApp.register()` / `unregister()` — simplest and recommended
- Check status with `SMAppService.mainApp.status` — it can be `.notRegistered`, `.enabled`, `.requiresApproval`, or `.notFound`
- Handle `.requiresApproval` — direct user to System Settings > General > Login Items
- Do NOT register on every app launch — check status first, register only on user action
- Store the user's preference in UserDefaults and reconcile with actual system state on launch
- Test with the archived/signed app, not Xcode debug builds (Launch at Login doesn't work in debug)
- Consider using the `LaunchAtLogin` Swift package (sindresorhus) for a battle-tested implementation

**Warning signs:** Launch at Login works in development but not production, duplicate app instances, setting doesn't persist across macOS updates.

**Phase to address:** Feature implementation — relatively self-contained.

---

### Pitfall 13: Config File Corruption and Atomicity

**What goes wrong:** The external config file (JSON/YAML/TOML) is partially written during a crash or power loss, resulting in a corrupted file that crashes the app on next launch. Or, the config is read while being written, producing garbled data.

**Why it happens:** `Data.write(to:)` with default options is not atomic. If the app crashes mid-write, the file is truncated. If using `String.write(to:)`, it's even less safe. Reading and writing from different threads without synchronization causes data races.

**How to avoid:**
- Always write atomically: `data.write(to: url, options: .atomic)` — this writes to a temp file then renames, which is atomic on APFS
- Serialize all config reads/writes through a single actor or serial DispatchQueue
- Keep a backup: before writing new config, rename current config to `.bak`
- Validate config on load — if parsing fails, fall back to `.bak`, then to built-in defaults
- Use `Codable` with `JSONEncoder` / `JSONDecoder` for type-safe serialization
- Consider using UserDefaults for simple config (it handles atomicity internally) and reserve file-based config for complex/user-editable settings
- Watch the config file for external changes (user edits in text editor) using `DispatchSource.makeFileSystemObjectSource`

```swift
// Anti-pattern:
try jsonData.write(to: configURL)

// Correct:
try jsonData.write(to: configURL, options: [.atomic, .completeFileProtection])
```

**Warning signs:** App crashes on launch after force-quit, config "resets" randomly, settings lost after crash.

**Phase to address:** Config module implementation.

---

### Pitfall 14: Duplicate Detection Across Formats Is Harder Than Expected

**What goes wrong:** A file exists as both `track.aiff` and `track.wav` (or `track (1).aiff` from browser re-download). Simple filename comparison doesn't catch these. Audio fingerprinting is too slow. Metadata-based matching (title, duration, sample rate) has false positives.

**Why it happens:** Duplicate semantics are ambiguous: same content in different formats? Same filename with different content? Same audio but different metadata? Browser re-downloads append ` (1)`, ` (2)` etc.

**How to avoid:**
- Define "duplicate" clearly and document it — suggest: same base filename (stripping extensions and browser suffixes like ` (1)`, ` (2)`) AND similar file size (within 10%) OR same duration
- Strip browser duplicate suffixes with regex: `(.+?)(?:\s*\(\d+\))?(\.[^.]+)$`
- For cross-format duplicates: compare duration (via ffprobe) with ±1 second tolerance AND sample rate
- Use file content hashing (SHA-256 of first 1MB + last 1MB + file size) for same-format exact duplicates — fast enough for most files
- Never auto-delete duplicates — move to a "Duplicates" folder or prompt user
- Cache file hashes/metadata in a lightweight database (SQLite via GRDB or even a JSON file) to avoid re-scanning

**Warning signs:** Duplicate files not caught, non-duplicates incorrectly flagged, slow scanning on large libraries.

**Phase to address:** Feature implementation — can iterate after core pipeline works.

---

### Pitfall 15: SwiftUI Menu Bar (MenuBarExtra) Limitations

**What goes wrong:** `MenuBarExtra` (macOS 13+) has limited customization compared to `NSStatusItem`. Complex views don't render correctly, the popover dismissal behavior is buggy, and there's no way to show a progress indicator in the menu bar icon natively.

**Why it happens:** `MenuBarExtra` is still relatively new and SwiftUI's AppKit bridge has gaps. Custom views in menu bar popovers have focus, sizing, and animation issues.

**How to avoid:**
- Use `MenuBarExtra` with `.window` style for custom SwiftUI views (settings, file list)
- For the actual menu (quick actions), use `.menu` style — it's more reliable
- For dynamic status icons (processing spinner, error badge), fall back to `NSStatusItem` directly via an `AppDelegate`
- Wrap complex interactions in an `NSPopover` managed by `NSStatusItem` for full control
- Test extensively on macOS 13, 14, and 15 — behavior differs between versions
- Consider a hybrid approach: `NSStatusItem` for the icon + `MenuBarExtra` for the settings window

**Warning signs:** Menu bar popover doesn't dismiss when clicking outside, layout breaks at different text sizes, icon doesn't update dynamically.

**Phase to address:** UI implementation.

---

### Pitfall 16: DispatchSource File Monitor Descriptor Leaks

**What goes wrong:** Creating `DispatchSource.makeFileSystemObjectSource` requires opening a file descriptor (`open(path, O_EVTONLY)`). If sources are created but not properly cancelled, or if the watched directory is deleted and recreated, file descriptors leak. macOS limits per-process descriptors (default ~256, soft limit ~10240).

**Why it happens:** Each `DispatchSource` holds an `fd`. If you recreate watchers (e.g., after wake from sleep) without cancelling old ones, descriptors accumulate. The `deinit` of the source doesn't automatically close the fd.

**How to avoid:**
- Always call `source.cancel()` before creating a new source for the same path
- Close the file descriptor in the `cancelHandler`: `source.setCancelHandler { close(fd) }`
- Keep a strong reference to the source — if it's deallocated without cancellation, the fd leaks
- Use a dedicated manager class that owns all sources and handles cleanup
- Prefer `FileManager`-level APIs or `NSFilePresenter` if you don't need low-level control
- Consider using `EonilFSEvents` or similar Swift wrapper for FSEvents (handles cleanup properly)

**Warning signs:** "Too many open files" error after extended use, file watcher silently stops working.

**Phase to address:** File watcher implementation.

---

### Pitfall 17: ffmpeg Binary Bundling and PATH Issues

**What goes wrong:** The app assumes ffmpeg is installed via Homebrew (`/opt/homebrew/bin/ffmpeg` or `/usr/local/bin/ffmpeg`). It's not found on user machines. Or, different versions of ffmpeg have different flags, causing conversion failures.

**Why it happens:** ffmpeg is not included with macOS. Homebrew paths differ between Intel (`/usr/local`) and Apple Silicon (`/opt/homebrew`). Users may have outdated versions or static builds with different codec support.

**How to avoid:**
- Bundle a static ffmpeg binary inside the app bundle (`Contents/Resources/ffmpeg` or `Contents/Frameworks/ffmpeg`)
- If bundling, use a GPL-compliant static build or build your own LGPL version
- Reference it via `Bundle.main.url(forResource: "ffmpeg", withExtension: nil)`
- If relying on system ffmpeg, search multiple paths: `/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg`, then `which ffmpeg` via shell
- Pin the minimum ffmpeg version and check with `ffmpeg -version` on first run
- Document ffmpeg as a dependency with installation instructions if not bundling
- For sandboxed apps: bundled binaries must be in `Contents/MacOS/` or `Contents/Helpers/` and code-signed

**Warning signs:** Works on dev machine, fails on user machines, ARM vs Intel issues, codec not found errors.

**Phase to address:** Project setup and distribution planning.

---

### Pitfall 18: AIFF Format Quirks

**What goes wrong:** AIFF conversion or reading fails for specific AIFF variants. AIFF-C (compressed AIFF) is a different format than AIFF. Some DAWs write non-standard AIFF chunks that confuse parsers. Big-endian byte order (AIFF) vs little-endian (WAV) causes issues in manual parsing.

**Why it happens:** AIFF is a container format with variants (AIFF, AIFF-C/aifc). The spec allows arbitrary chunks. DAWs like Logic Pro, Pro Tools, and Ableton each write slightly different AIFF files with custom metadata chunks (e.g., `ANNO`, `AUTH`, `MARK`, `INST`).

**How to avoid:**
- Use ffmpeg/ffprobe for all format detection and conversion — it handles AIFF variants reliably
- Don't manually parse AIFF unless necessary — if you must, handle both `AIFF` and `AIFC` form types
- When converting to AIFF, specify format explicitly: `ffmpeg -i input.wav -f aiff -acodec pcm_s16be output.aiff`
- Specify bit depth explicitly to avoid surprises: `-acodec pcm_s16be` (16-bit), `pcm_s24be` (24-bit), `pcm_s32be` (32-bit)
- Preserve metadata during conversion: `-map_metadata 0`
- Test with AIFF files from multiple DAWs (Logic, Ableton, Pro Tools, FL Studio)

**Warning signs:** Conversion works for some AIFF files but not others, metadata lost during conversion, "codec not found" for AIFF-C files.

**Phase to address:** Audio processing implementation.

---

### Pitfall 19: Swift Concurrency + File I/O Foot Guns

**What goes wrong:** Using `async/await` with `actor` isolation for file operations causes unexpected serialization. An actor processing files becomes a bottleneck because file I/O blocks the actor's serial executor. Alternatively, `@Sendable` closures with captured mutable state cause data races flagged by the Swift 6 strict concurrency checker.

**Why it happens:** Swift actors serialize access, which is correct for data protection but catastrophic for performance when the protected operations are I/O-bound. File I/O in Swift is synchronous under the hood — `Data(contentsOf:)`, `FileManager.moveItem` — and blocks the cooperative thread pool.

**How to avoid:**
- Keep file I/O off actors — use `nonisolated` methods or detach to a custom serial `DispatchQueue`
- Use `DispatchQueue` (not actors) for I/O-heavy work — actors are for data protection, not I/O coordination
- If using actors, yield control with `await Task.yield()` between heavy operations
- Use `CheckedContinuation` to bridge callback-based APIs (Process terminationHandler) to async/await
- Enable strict concurrency checking (`-strict-concurrency=complete`) early to catch issues at compile time
- Be careful with `MainActor` — menu bar UI updates must be on MainActor, but file processing must not be

**Warning signs:** UI freezes during file processing, processing is slower than expected, Swift concurrency warnings/errors accumulate in later Xcode versions.

**Phase to address:** Architecture — concurrency model design.

---

### Pitfall 20: Notification / User Feedback Overload

**What goes wrong:** Sending a macOS notification for every processed file (especially during batch processing of 50+ files) overwhelms the user and Notification Center. macOS may throttle or suppress notifications. Alternatively, providing no feedback leaves users unsure if the app is working.

**Why it happens:** No batching or rate-limiting of notifications. Each file triggers its own `UNUserNotificationCenter.add()` call.

**How to avoid:**
- Batch notifications: "Organized 15 files" instead of 15 individual notifications
- Use a debounce window (5 seconds) — accumulate processed files and send one summary notification
- Show real-time status in the menu bar icon itself (e.g., badge count, processing indicator via SF Symbols animation)
- Request notification permission gracefully — explain why before the system prompt
- Provide a "quiet mode" toggle in settings
- Use `UNNotificationCategory` with actions ("Show in Finder", "Undo") for actionable notifications

**Warning signs:** Users disable notifications for the app, Notification Center is flooded, no feedback that the app is working.

**Phase to address:** UX design and implementation.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| Hardcoded ~/Downloads path | Quick to implement | Breaks if user changes default downloads folder, doesn't support multiple watched folders | Prototype only. Use `FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)` from the start |
| `shell("ffmpeg ...")` via `Process("/bin/zsh", ["-c", cmd])` | Easy string interpolation for ffmpeg commands | Shell injection risk, quoting issues with filenames containing spaces/quotes/unicode, performance overhead of shell fork | Never — always use `Process` with argument array directly |
| Polling-based file watcher (Timer checking directory) | Simple, no FSEvents complexity | Battery drain, delayed detection, misses rapid changes | Only as a fallback when DispatchSource fails |
| Global mutable state for processing queue | Quick access from anywhere | Race conditions, untestable, impossible to reason about in concurrent context | Never — use a proper queue/actor/manager pattern |
| Synchronous LLM API calls | Simpler control flow | Blocks thread pool, UI freezes, no timeout control | Never — always use async URLSession with timeout |
| String-based file type detection (extension only) | Fast, no I/O needed | Misidentifies files with wrong extensions, security risk | Acceptable as first-pass filter, but verify with magic bytes for processing |
| No config file versioning | Less code | Config format changes break existing installations, no migration path | Only in very early prototyping |
| `try!` and `fatalError` for file operations | Crashes surface bugs immediately | Crashes in production for edge cases (permissions, disk full, network drives) | Never in production — always handle errors gracefully |
| Bundling ffmpeg without license compliance | Works immediately | Legal exposure (GPL violation if not open-sourcing, LGPL requires dynamic linking) | Never — understand and comply with ffmpeg licensing |
| Single-file config (no schema validation) | Simple read/write | Corrupted config crashes app, no migration between versions, no type safety | Early prototype only |

---

## Security Considerations

### File Path Injection
- **Risk:** Filenames from ~/Downloads are user-controlled (and can contain malicious characters)
- **Mitigation:** Never interpolate filenames into shell commands. Use `Process` with argument arrays. Validate filenames before processing.
- **Example attack:** A file named `; rm -rf ~/` could cause damage if passed through a shell

### ffmpeg Command Injection
- **Risk:** If filenames are interpolated into ffmpeg command strings, special characters can inject commands
- **Mitigation:** Always pass file paths as separate arguments to `Process`, never through shell interpretation
```swift
// DANGEROUS:
process.arguments = ["-c", "ffmpeg -i '\(inputPath)' '\(outputPath)'"]

// SAFE:
process.executableURL = ffmpegURL
process.arguments = ["-i", inputPath, outputPath]
```

### Quarantine and Gatekeeper
- **Risk:** Files in ~/Downloads have `com.apple.quarantine` xattr. Moving them preserves this. Your app may trigger Gatekeeper warnings when users open organized files
- **Mitigation:** Understand that quarantine is a security feature — don't strip it. If converting files (ffmpeg), the output files won't have quarantine (which is correct)

### LM Studio API Security
- **Risk:** LM Studio binds to localhost by default, but if configured to bind to 0.0.0.0, the API is exposed to the network. PDF content is sent to the API.
- **Mitigation:** Always connect to `127.0.0.1`, not `0.0.0.0`. Document that PDF content stays local. Don't log PDF content.

### Permissions Escalation
- **Risk:** The app requests broad file system access but should only need ~/Downloads and user-designated output folders
- **Mitigation:** Request minimum necessary permissions. Use Security-Scoped Bookmarks for user-chosen directories. Never request Full Disk Access unless absolutely necessary.

### Code Signing and Notarization
- **Risk:** Unsigned/un-notarized apps are blocked by default on macOS. Bundled ffmpeg binary must also be signed.
- **Mitigation:** Sign with Developer ID, notarize via `notarytool`, sign ffmpeg binary with `codesign --sign "Developer ID" --options runtime`

---

## Performance Considerations

### Memory Budget
- **Target:** < 50MB RSS when idle, < 200MB during active processing
- **Risk areas:**
  - Loading large audio files into memory (use streaming/header-only reads)
  - PDF text extraction of large documents (process page-by-page, limit to first 5 pages for classification)
  - Accumulated log/history data (cap in-memory history, use rolling log files)
  - SwiftUI view body re-evaluation (use `@Observable` / `@StateObject` correctly to prevent unnecessary redraws)

### CPU Budget
- **Target:** < 1% CPU when idle (no active file events)
- **Risk areas:**
  - Polling-based file watching (use event-driven FSEvents instead)
  - Timer-based status updates (use event-driven updates)
  - SwiftUI animation in menu bar (keep simple, avoid continuous animations)
  - ffmpeg processes should use `-threads` flag appropriately (default is fine for most cases)

### Disk I/O
- **Risk:** Simultaneous ffmpeg conversions cause disk I/O contention, slowing down the system
- **Mitigation:** Limit concurrent conversions (2–3 max). Use sequential I/O where possible. Avoid unnecessary temp files.
- **SSD consideration:** Modern Mac SSDs handle concurrent writes well, but conversion of very large files (>1GB) should still be serialized

### Battery Impact
- **Target:** Minimal battery impact when idle — app should not appear in "Using Significant Energy" warning
- **Risk areas:**
  - File watcher keeping CPU awake (use coalesced FSEvents, not raw `kqueue`)
  - Network requests to LM Studio keeping Wi-Fi active (batch requests, don't poll)
  - Unnecessary Timer instances (audit and remove/lengthen intervals)
- **Mitigation:** Use `QualityOfService.utility` or `.background` for non-urgent processing. Test with Activity Monitor's Energy tab.

### Startup Time
- **Target:** < 1 second to menu bar icon visible
- **Risk:** Loading config, checking LM Studio, scanning ~/Downloads on launch
- **Mitigation:** Show icon immediately, load everything else asynchronously. Defer initial scan until after UI is ready. Cache last known state.

---

## Platform Version Matrix

| Feature | macOS 13 (Ventura) | macOS 14 (Sonoma) | macOS 15 (Sequoia) |
|---|---|---|---|
| `MenuBarExtra` | Supported (basic) | Improved sizing | Stable |
| `SMAppService` (Launch at Login) | Introduced | Stable | Stable |
| `Observable` macro | N/A | Introduced | Stable |
| Strict concurrency | Warnings only | Warnings | Enforced (Swift 6) |
| FSEvents API | Stable | Stable | Stable |
| Notification permissions | Required | Required | Stricter |

**Minimum deployment target recommendation:** macOS 14 (Sonoma) — balances modern API availability with user base coverage. macOS 13 if `@Observable` isn't critical.
