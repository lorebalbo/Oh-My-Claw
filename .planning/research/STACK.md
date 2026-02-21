# Stack Research

**Domain:** macOS Menu Bar File Organizer (Audio + PDF classification)
**Researched:** 2026-02-21
**Confidence:** HIGH

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|---|---|---|---|
| **Swift** | 5.10+ | Primary language | Native macOS performance, strong concurrency model with `async/await` and structured concurrency, first-class Apple framework support |
| **SwiftUI** | macOS 13+ (Ventura) | Menu bar UI | `MenuBarExtra` API (introduced macOS 13) is the modern, Apple-blessed way to build menu bar apps — replaces legacy `NSStatusItem` hacks |
| **Swift Package Manager** | Built-in | Dependency management | First-party, no external tooling needed, Xcode-integrated |
| **Swift Concurrency** | Built-in | Parallelism (ffmpeg, file ops) | `TaskGroup` for concurrent ffmpeg conversions bounded to CPU core count; `AsyncStream` for file watcher events; eliminates callback hell |

### Supporting Libraries / Frameworks

| Library / Framework | Version | Purpose | When to Use |
|---|---|---|---|
| **FSEvents (CoreServices)** | System | Real-time file system monitoring | Primary file watcher for ~/Downloads — kernel-level, low-overhead, reliable. Use `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents` for per-file granularity |
| **AVFoundation** | System | Audio metadata reading + duration | Read duration, format info, and basic metadata (title, artist, album) from audio files via `AVAsset` / `AVAssetTrack`. Supports all Apple-decoded formats (MP3, AAC, ALAC, FLAC, WAV, AIFF, CAF) |
| **AudioToolbox** | System | Audio format detection | `AudioFileGetGlobalInfo` and `ExtAudioFile` APIs for detailed codec/bitrate/sample-rate introspection when AVFoundation metadata is insufficient |
| **Foundation Process** | System | ffmpeg execution | `Process` (formerly `NSTask`) for spawning ffmpeg subprocesses. Use `Pipe` for stdout/stderr capture. Wrap in `async` with `withCheckedContinuation` for clean concurrency integration |
| **URLSession** | System | LM Studio HTTP API calls | Built-in async/await support, no external deps. `URLSession.shared.data(for:)` for POST requests to `http://localhost:1234/v1/chat/completions` |
| **OSLog / Logger** | System | Structured logging | Apple's unified logging system. Logs appear in Console.app, persist to disk, support log levels and categories. Use `Logger(subsystem:category:)` |
| **SMAppService** | macOS 13+ | Launch at Login | Modern replacement for `SMLoginItemSetEnabled`. One-line API: `SMAppService.mainApp.register()`. No helper app needed |
| **UserNotifications** | System | Error notifications | `UNUserNotificationCenter` for native macOS notifications on conversion failures, classification errors, etc. |
| **PDFKit** | System | PDF text extraction | `PDFDocument` + `PDFPage.string` for extracting text content from PDFs before sending to LM Studio for classification |

### Development Tools

| Tool | Purpose | Notes |
|---|---|---|
| **Xcode 16+** | IDE, build system, signing | Required for SwiftUI previews, menu bar app target, sandbox configuration |
| **ffmpeg** (Homebrew) | Audio format conversion | Install via `brew install ffmpeg`. Bundle path in config or detect via `which ffmpeg`. Target command: `ffmpeg -i input -f aiff -acodec pcm_s16be output.aiff` |
| **SwiftLint** | Code style enforcement | SPM plugin: `https://github.com/realm/SwiftLint` — keeps codebase consistent |
| **Instruments** | Performance profiling | Monitor memory/CPU during concurrent ffmpeg conversions |
| **LM Studio** | Local LLM inference | OpenAI-compatible API at `localhost:1234`. No SDK needed — raw HTTP via URLSession |

---

## Detailed Technology Decisions

### 1. Menu Bar App Architecture

```
App (SwiftUI)
├── @main App struct with MenuBarExtra
├── MenuBarExtra("Oh My Claw", systemImage: "arrow.down.doc") { ... }
│   ├── Toggle: On / Off
│   ├── Button: Pause
│   ├── Button: Open Config
│   └── Status info (files processed, errors)
└── No main window (set LSUIElement = true in Info.plist)
```

**Use `MenuBarExtra` with `.menuBarExtraStyle(.menu)` for a simple dropdown**, or `.menuBarExtraStyle(.window)` if you need a richer popover UI with sliders/forms for config editing.

Set `LSUIElement` (Application is agent) to `YES` in Info.plist to hide the dock icon.

### 2. File System Monitoring — FSEvents

**Recommended: `DispatchSource.makeFileSystemObjectSource` for single-directory watching, wrapped in an `AsyncStream`.**

```swift
// Preferred pattern: FSEvents via CoreServices for ~/Downloads
func watchDownloads() -> AsyncStream<[String]> {
    AsyncStream { continuation in
        var context = FSEventStreamContext(...)
        let stream = FSEventStreamCreate(
            nil, callback, &context,
            [NSString(string: downloadsPath)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency (batching)
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        FSEventStreamSetDispatchQueue(stream!, DispatchQueue(label: "fsevents"))
        FSEventStreamStart(stream!)
    }
}
```

**Why FSEvents over DispatchSource:** FSEvents handles subdirectory changes, survives across renames, and is the macOS-native solution for directory monitoring. `DispatchSource.makeFileSystemObjectSource` only monitors a single file descriptor and doesn't provide per-file event details.

**Important:** Add a short debounce (1–2 seconds) — files being downloaded appear as partial/temporary files before completion. Check file size stability or use `NSFileCoordinator` to confirm write completion.

### 3. Audio Metadata & Format Detection

**Two-layer approach:**

| Layer | Framework | What It Reads |
|---|---|---|
| **Primary** | `AVFoundation` (`AVAsset`, `AVMetadataItem`) | Duration, title, artist, album, format (via `AVAssetTrack.mediaType` / `formatDescriptions`) |
| **Fallback** | `AudioToolbox` (`AudioFileOpenURL`, `kAudioFilePropertyDataFormat`) | Bitrate, codec, sample rate, bit depth for format ranking decisions |

**Why not TagLib?** TagLib Swift bindings (e.g., `SotoTagLib`) exist but add a C++ dependency, complicate the build, and AVFoundation already reads ID3/Vorbis/MP4 metadata natively. Only consider TagLib if you need to *write* metadata.

```swift
let asset = AVURLAsset(url: fileURL)
let duration = try await asset.load(.duration) // CMTime
let metadata = try await asset.load(.commonMetadata)
let title = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle).first
```

### 4. Process Management for ffmpeg

**Recommended: `Foundation.Process` wrapped in async/await with `TaskGroup` for concurrency.**

```swift
func convert(input: URL, output: URL) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    process.arguments = ["-i", input.path, "-f", "aiff", "-acodec", "pcm_s16be", "-y", output.path]
    
    let stderr = Pipe()
    process.standardError = stderr
    
    return try await withCheckedThrowingContinuation { continuation in
        process.terminationHandler = { proc in
            if proc.terminationStatus == 0 {
                continuation.resume()
            } else {
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(throwing: ConversionError.ffmpegFailed(String(data: errorData, encoding: .utf8) ?? ""))
            }
        }
        try? process.run()
    }
}

// Concurrent conversions bounded to CPU cores
let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount
await withTaskGroup(of: Void.self) { group in
    for file in filesToConvert {
        await group.waitForAll() // throttle if needed
        group.addTask { try? await convert(input: file.input, output: file.output) }
    }
}
```

**Use a custom `TaskGroup` with semaphore-style throttling** (or an `AsyncSemaphore` from `swift-async-algorithms`) to cap concurrent ffmpeg processes to `ProcessInfo.processInfo.activeProcessorCount`.

### 5. HTTP Networking — LM Studio API

**Recommended: Native `URLSession` with `Codable` models.**

```swift
struct ChatRequest: Codable {
    let model: String
    let messages: [Message]
    let temperature: Double
}

struct Message: Codable {
    let role: String
    let content: String
}

func classifyPDF(text: String) async throws -> Bool {
    var request = URLRequest(url: URL(string: "http://localhost:1234/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(ChatRequest(
        model: "local-model",
        messages: [.init(role: "system", content: "Classify if this is a scientific paper. Reply only YES or NO."),
                   .init(role: "user", content: text)],
        temperature: 0.1
    ))
    let (data, _) = try await URLSession.shared.data(for: request)
    let response = try JSONDecoder().decode(ChatResponse.self, from: data)
    return response.choices.first?.message.content.uppercased().contains("YES") ?? false
}
```

**Why not Alamofire / OpenAI Swift SDK?** The LM Studio API surface is tiny (one endpoint). URLSession handles it cleanly with zero dependencies. Adding Alamofire or an OpenAI SDK would be disproportionate.

### 6. JSON Configuration Management

**Recommended: `Codable` struct + `JSONDecoder`/`JSONEncoder`, persisted to `~/Library/Application Support/OhMyClaw/config.json`.**

```swift
struct AppConfig: Codable {
    var requiredMetadataFields: [String]       // ["title", "artist", "album"]
    var minimumDurationSeconds: Int             // 60
    var formatRanking: [FormatRank]             // [{format: "FLAC", position: 1}, ...]
    var conversionThresholdPosition: Int        // 3
    var ffmpegPath: String                      // "/opt/homebrew/bin/ffmpeg"
    var lmStudioEndpoint: String                // "http://localhost:1234"
    var lmStudioModel: String                   // "local-model"
    var maxConcurrentConversions: Int?           // nil = auto (CPU cores)
    var musicDestination: String                // "~/Music"
    var papersDestination: String               // "~/Documents/Papers"
}
```

Use `FileManager.default.urls(for: .applicationSupportDirectory)` for the config file location. Watch the config file with FSEvents for live-reload when edited externally.

### 7. Logging

**Recommended: `OSLog` / `Logger` (system framework) + supplementary log file.**

```swift
import OSLog

extension Logger {
    static let fileWatcher = Logger(subsystem: "com.ohmyclaw.app", category: "FileWatcher")
    static let conversion = Logger(subsystem: "com.ohmyclaw.app", category: "Conversion")
    static let classification = Logger(subsystem: "com.ohmyclaw.app", category: "Classification")
}

// Usage
Logger.conversion.info("Converting \(file.lastPathComponent) to AIFF")
Logger.conversion.error("ffmpeg failed: \(errorMessage)")
```

For the **persistent log file** requirement, supplement OSLog with a simple `FileHandle`-based writer to `~/Library/Logs/OhMyClaw/ohmyclaw.log`, or use `OSLogStore` (macOS 12+) to query recent logs programmatically.

### 8. Launch at Login

**Recommended: `SMAppService` (macOS 13+, ServiceManagement framework).**

```swift
import ServiceManagement

func enableLaunchAtLogin() throws {
    try SMAppService.mainApp.register()
}

func disableLaunchAtLogin() throws {
    try SMAppService.mainApp.unregister()
}

var isLaunchAtLoginEnabled: Bool {
    SMAppService.mainApp.status == .enabled
}
```

**No helper app required.** This is vastly simpler than the legacy `SMLoginItemSetEnabled` + helper bundle approach.

### 9. Testing

| Framework | Purpose | Notes |
|---|---|---|
| **XCTest** | Unit + integration tests | Built-in, test config parsing, format ranking logic, metadata extraction |
| **Swift Testing** (`@Test`, `#expect`) | Modern unit tests | Available Swift 5.10+/Xcode 16. Cleaner syntax than XCTest, parameterized tests for format ranking |
| **XCTest + Process** | ffmpeg integration tests | Spawn real ffmpeg with test audio files, verify AIFF output |
| **URLProtocol mock** | LM Studio API tests | Subclass `URLProtocol` to intercept HTTP requests — no mock library needed |

```swift
// Swift Testing example
@Test("Audio files shorter than threshold are rejected", arguments: [30, 59, 60, 120])
func durationFilter(seconds: Int) {
    let config = AppConfig(minimumDurationSeconds: 60, ...)
    #expect(config.shouldProcess(duration: seconds) == (seconds >= 60))
}
```

---

## Installation / Setup

### 1. Create the Xcode Project
```bash
# Xcode > File > New > Project > macOS > App
# Product Name: OhMyClaw
# Interface: SwiftUI
# Language: Swift
# Bundle Identifier: com.ohmyclaw.app
```

### 2. Configure as Menu Bar App
- In **Info.plist**, add: `LSUIElement` (Application is agent) = `YES`
- Use `MenuBarExtra` in main `App` struct (requires deployment target macOS 13+)

### 3. Entitlements & Sandbox
- **Disable App Sandbox** (required for: accessing ~/Downloads, ~/Music, ~/Documents, spawning ffmpeg, localhost networking)
- Alternatively, keep sandbox and add:
  - `com.apple.security.files.user-selected.read-write`
  - `com.apple.security.network.client`
  - `com.apple.security.temporary-exception.files.absolute-path.read-write` (for ffmpeg)
- **Recommendation: Run without sandbox** for this use case. The app accesses arbitrary user directories and spawns external processes — sandboxing would require extensive exceptions that negate its benefits.

### 4. Install ffmpeg
```bash
brew install ffmpeg
# Default location: /opt/homebrew/bin/ffmpeg (Apple Silicon)
#                   /usr/local/bin/ffmpeg (Intel)
```

### 5. Add SPM Dependencies (if any)
```
# Package.swift or Xcode > File > Add Package Dependencies
# No external packages are strictly required for the recommended stack.
# Optional:
#   - swift-async-algorithms (for AsyncChannel, throttle, debounce)
#     https://github.com/apple/swift-async-algorithms — 1.0+
```

### 6. Set Deployment Target
- **macOS 13.0 (Ventura)** minimum — required for `MenuBarExtra` and `SMAppService`
- macOS 14.0 (Sonoma) recommended for latest SwiftUI improvements

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|---|---|---|
| `MenuBarExtra` (SwiftUI) | `NSStatusItem` + `NSMenu` (AppKit) | If you need macOS 12 support, or need pixel-perfect control over the menu (custom NSViews in menu items) |
| FSEvents (CoreServices) | `DispatchSource.makeFileSystemObjectSource` | Only for monitoring a single known file (not a directory's contents) |
| FSEvents (CoreServices) | `NSMetadataQuery` (Spotlight) | If you want to query files by metadata attributes rather than watch for filesystem events |
| `AVFoundation` | TagLib (via `SotoTagLib` or C bindings) | If you need to *write* metadata back to files, or read obscure tag formats not supported by AVFoundation |
| `AVFoundation` | `MediaPlayer` / `MusicKit` | Never — these are for playback/library access, not file introspection |
| `Foundation.Process` | `ShellOut` SPM package | If you want a slightly cleaner API for shell commands, but it adds a dependency for minimal gain |
| `URLSession` | Alamofire | If the LM Studio integration grows complex (retries, interceptors, multipart) — unlikely for this use case |
| `URLSession` | `MacPaw/OpenAI` Swift SDK | If you want typed models for the OpenAI API — but adds dependency and may lag behind LM Studio quirks |
| `OSLog` / `Logger` | `SwiftyBeaver`, `CocoaLumberjack` | If you need log file rotation, colored console output, or remote logging — overkill for this project |
| `SMAppService` | `LaunchAtLogin` SPM (by Sindre Sorhus) | Wraps SMAppService with a SwiftUI `Toggle` binding — nice convenience, small dependency |
| `Codable` JSON config | `@AppStorage` / `UserDefaults` | For simple key-value preferences; JSON file is better for complex nested config + external editability |
| `Codable` JSON config | YAML / TOML config | Only if users strongly prefer YAML/TOML — requires third-party parser (Yams, TOMLKit) |
| Swift Testing | Quick/Nimble | If you prefer BDD-style tests — but Swift Testing's built-in parameterized tests cover most needs |
| No dependency for concurrency throttle | `swift-async-algorithms` | If you want `AsyncChannel`, `debounce`, `throttle` operators — useful for FSEvents debouncing |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|---|---|---|
| **`Timer.scheduledTimer` polling** | Wasteful CPU usage, misses rapid changes, adds latency | FSEvents for event-driven file watching |
| **`FileManager.contentsOfDirectory` polling loop** | Same as above — polling is an anti-pattern for file monitoring | FSEvents |
| **`NSAppleScript` / `osascript`** | Fragile, slow, no error handling, sandboxing issues | Native Swift APIs for everything |
| **Electron / web-based menu bar** | 100MB+ RAM for a menu bar icon, non-native UX | SwiftUI `MenuBarExtra` |
| **`GCD` callback-based concurrency** | Callback hell, hard to reason about, race conditions | Swift `async/await` + `TaskGroup` |
| **`SMLoginItemSetEnabled` (legacy)** | Deprecated, requires companion helper app bundle, complex setup | `SMAppService.mainApp.register()` |
| **`NSStatusItem` manual setup** | Boilerplate-heavy, imperative, no SwiftUI preview support | `MenuBarExtra` (SwiftUI) |
| **App Sandbox (strict)** | This app needs ~/Downloads, ~/Music, ~/Documents access + ffmpeg process spawning + localhost networking — sandboxing requires so many exceptions it becomes meaningless | Hardened Runtime without sandbox |
| **`Combine` for new async work** | Apple is steering toward `async/await`; Combine adds complexity without benefit here | Swift Concurrency (`async/await`, `AsyncStream`, `TaskGroup`) |
| **Core Data** | No relational data model needed; over-engineered for config + CSV logging | `Codable` JSON + plain text CSV |
| **Realm / SQLite** | Same as above — no database use case | Flat files |
| **`swift-argument-parser`** | This is a GUI app, not a CLI tool | `MenuBarExtra` UI for configuration |

---

## macOS Version Compatibility

| API / Feature | Minimum macOS | Notes |
|---|---|---|
| `MenuBarExtra` | **macOS 13.0** (Ventura) | Core UI component — sets the floor for deployment target |
| `SMAppService` | **macOS 13.0** (Ventura) | Launch at Login — same minimum as MenuBarExtra |
| `MenuBarExtra(.window)` style | **macOS 13.0** (Ventura) | For popover-style rich UI |
| Swift `async/await` | macOS 12.0 (Monterey) | Below the MenuBarExtra floor, so not a constraint |
| `TaskGroup` | macOS 12.0 (Monterey) | Same |
| `AVAsset.load(_:)` async | macOS 12.0 (Monterey) | Preferred over deprecated synchronous property access |
| `OSLog` / `Logger` | macOS 11.0 (Big Sur) | Well below the floor |
| FSEvents | macOS 10.5+ | Ancient, universally available |
| `PDFKit` | macOS 10.4+ | Universally available |
| `AVFoundation` metadata | macOS 10.7+ | Universally available |
| `UserNotifications` | macOS 10.14+ | Well below the floor |
| `Observable` macro (`@Observable`) | **macOS 14.0** (Sonoma) | Optional — use `ObservableObject` if targeting macOS 13 |
| `.onChange(of:)` two-parameter | **macOS 14.0** (Sonoma) | Use one-parameter version on macOS 13 |

### Recommended Deployment Target: **macOS 13.0 (Ventura)**

This is dictated by `MenuBarExtra` and `SMAppService`. As of February 2026, macOS 13 is three releases old (13 → 14 → 15 → 16), covering the vast majority of active Macs. If you want `@Observable` and newer SwiftUI APIs, bump to macOS 14.0.

---

## Project Structure (Recommended)

```
OhMyClaw/
├── OhMyClawApp.swift              # @main, MenuBarExtra
├── Views/
│   ├── MenuBarView.swift          # Menu bar dropdown content
│   └── ConfigEditorView.swift     # Config editing UI (window)
├── Services/
│   ├── FileWatcher.swift          # FSEvents wrapper → AsyncStream
│   ├── AudioProcessor.swift       # Metadata reading, format ranking, move logic
│   ├── AudioConverter.swift       # ffmpeg Process wrapper, concurrent conversion
│   ├── PDFClassifier.swift        # PDFKit text extraction + LM Studio API
│   └── ConfigManager.swift        # JSON config load/save/watch
├── Models/
│   ├── AppConfig.swift            # Codable config struct
│   ├── AudioFileInfo.swift        # Parsed audio file metadata
│   └── FormatRank.swift           # Format ranking model
├── Utilities/
│   ├── Logging.swift              # Logger extensions + file logger
│   ├── Notifications.swift        # UNUserNotificationCenter helpers
│   └── ProcessRunner.swift        # Generic async Process wrapper
├── Resources/
│   └── default-config.json        # Bundled default configuration
└── Tests/
    ├── AudioProcessorTests.swift
    ├── ConfigManagerTests.swift
    ├── FormatRankingTests.swift
    └── PDFClassifierTests.swift
```

---

## Key Implementation Notes

1. **File write completion detection:** When monitoring ~/Downloads, files from browsers arrive incrementally. Check for `.crdownload` / `.part` / `.download` extensions and skip them. Also verify the file size hasn't changed over a 2-second window before processing.

2. **ffmpeg path resolution:** Don't hardcode `/opt/homebrew/bin/ffmpeg`. Store in config, with fallback to `which ffmpeg` via `Process`. Apple Silicon and Intel Macs have different Homebrew prefixes.

3. **Concurrent conversions:** Use `ProcessInfo.processInfo.activeProcessorCount` as the default max concurrency. Allow override via config. Each ffmpeg process is CPU-bound on one core.

4. **PDF text extraction limits:** For LM Studio classification, extract only the first 2–3 pages of text (`PDFDocument.page(at: 0...2)`). Sending the entire paper text would be slow and wasteful — the abstract/title/references on the first pages are sufficient for classification.

5. **LM Studio availability check:** Before classifying PDFs, ping `http://localhost:1234/v1/models` to verify LM Studio is running. Queue PDFs for retry if it's down. Show status in menu bar.

6. **CSV logging for low-quality files:** Use `FileHandle` to append rows. Don't load the entire CSV into memory. Format: `timestamp,filename,title,artist,album,format,bitrate`.
