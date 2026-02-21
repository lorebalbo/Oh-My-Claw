# Architecture Research

**Domain:** macOS Menu Bar File Organizer
**Researched:** 2026-02-21
**Confidence:** HIGH

---

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS Menu Bar                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              MenuBarView (SwiftUI)                        │  │
│  │  [■ On/Off] [⏸ Pause] [⚙ Config] [📊 Status]            │  │
│  └──────────────────────┬────────────────────────────────────┘  │
│                         │ @Published state                      │
│  ┌──────────────────────▼────────────────────────────────────┐  │
│  │              AppCoordinator (actor)                        │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐  │  │
│  │  │ ConfigStore │  │ TaskRegistry │  │ NotificationMgr │  │  │
│  │  └─────────────┘  └──────┬───────┘  └─────────────────┘  │  │
│  └──────────────────────────┼────────────────────────────────┘  │
│                             │                                   │
│  ┌──────────────────────────▼────────────────────────────────┐  │
│  │            FileWatcher (FSEvents)                          │  │
│  │  ~/Downloads → new file event                             │  │
│  └──────────────────────────┬────────────────────────────────┘  │
│                             │ FileEvent                         │
│  ┌──────────────────────────▼────────────────────────────────┐  │
│  │              TaskRouter                                    │  │
│  │  matches file → dispatches to registered task              │  │
│  └─────┬───────────────────────────────────┬─────────────────┘  │
│        │                                   │                    │
│  ┌─────▼─────────────────┐  ┌──────────────▼────────────────┐  │
│  │   AudioTask (module)  │  │    PDFTask (module)           │  │
│  │                       │  │                               │  │
│  │  ┌─ ValidateMetadata  │  │  ┌─ ExtractContent            │  │
│  │  ├─ CheckDuration     │  │  ├─ ClassifyViaLLM            │  │
│  │  ├─ DetectDuplicates  │  │  └─ MoveIfPaper               │  │
│  │  ├─ MoveToMusic       │  │                               │  │
│  │  ├─ EvaluateQuality   │  └───────────────────────────────┘  │
│  │  └─ ConvertOrArchive  │                                     │
│  │     ┌────────────┐    │                                     │
│  │     │ ffmpeg pool │    │                                     │
│  │     │ (N workers) │    │                                     │
│  │     └────────────┘    │                                     │
│  └───────────────────────┘                                     │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Cross-cutting: Logger · ErrorHandler · FileManager       │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|---------------|----------------------|
| **App Entry** | Bootstrap app as menu bar-only (no dock icon) | `@main App` with `MenuBarExtra`, `Info.plist` `LSUIElement = true` |
| **MenuBarView** | Render popover UI for controls and config | SwiftUI `MenuBarExtra` with `popover` style |
| **AppCoordinator** | Central orchestrator: owns watcher, registry, state | Swift `actor` — serializes state mutations |
| **ConfigStore** | Load/save/validate JSON config, publish changes | `ObservableObject` wrapping `Codable` structs |
| **FileWatcher** | Monitor ~/Downloads for new files via FSEvents | `DispatchSource.makeFileSystemObjectSource` or `EonilFSEvents` wrapper |
| **TaskRegistry** | Register/discover task modules, match files to tasks | Protocol-based registry with `[FileTask]` array |
| **TaskRouter** | Route incoming file events to matching tasks | Iterates registered tasks, calls `canHandle(file:)` |
| **AudioTask** | Full audio pipeline (validate → convert/archive) | Struct conforming to `FileTask` protocol |
| **PDFTask** | PDF classification pipeline | Struct conforming to `FileTask` protocol |
| **ConversionPool** | Bounded concurrent ffmpeg executions | `TaskGroup` or custom `AsyncSemaphore` with `ProcessInfo.processInfo.activeProcessorCount` |
| **LMStudioClient** | HTTP client for local LLM API | `URLSession` async calls to `localhost:1234` |
| **Logger** | Structured logging to file + console | `os.Logger` (unified logging) + rotating file logger |
| **NotificationManager** | Surface errors/completions to user | `UNUserNotificationCenter` |
| **LaunchAtLogin** | Toggle login item registration | `SMAppService.mainApp` (macOS 13+) |

---

## Recommended Project Structure

```
OhMyClaw/
├── OhMyClawApp.swift                  # @main, MenuBarExtra setup
├── Info.plist                          # LSUIElement=true, sandbox entitlements
│
├── App/
│   ├── AppCoordinator.swift            # Central actor coordinating all services
│   ├── AppState.swift                  # @Observable app-wide state
│   └── LaunchAtLogin.swift             # SMAppService wrapper
│
├── UI/
│   ├── MenuBarView.swift               # Main MenuBarExtra content view
│   ├── StatusView.swift                # Current processing status
│   ├── ConfigEditorView.swift          # Inline config editing
│   └── Components/
│       ├── ToggleRow.swift
│       └── SliderRow.swift
│
├── Config/
│   ├── AppConfig.swift                 # Top-level Codable config model
│   ├── AudioConfig.swift               # Audio-specific config section
│   ├── PDFConfig.swift                 # PDF-specific config section
│   └── ConfigStore.swift               # Load/save/watch JSON file
│
├── Core/
│   ├── FileWatcher.swift               # FSEvents wrapper
│   ├── TaskRouter.swift                # Routes files to matching tasks
│   ├── TaskRegistry.swift              # Registers and discovers tasks
│   └── Protocols/
│       ├── FileTask.swift              # Protocol all task modules implement
│       └── PipelineStep.swift          # Protocol for individual pipeline steps
│
├── Tasks/
│   ├── Audio/
│   │   ├── AudioTask.swift             # FileTask conformance, pipeline orchestration
│   │   ├── Steps/
│   │   │   ├── MetadataValidator.swift
│   │   │   ├── DurationChecker.swift
│   │   │   ├── DuplicateDetector.swift
│   │   │   ├── FileMover.swift
│   │   │   ├── QualityEvaluator.swift
│   │   │   └── AIFFConverter.swift
│   │   └── AudioModels.swift           # AudioFile, FormatRanking, etc.
│   │
│   └── PDF/
│       ├── PDFTask.swift               # FileTask conformance
│       ├── Steps/
│       │   ├── ContentExtractor.swift
│       │   ├── LLMClassifier.swift
│       │   └── PaperMover.swift
│       └── PDFModels.swift
│
├── Services/
│   ├── FFmpegService.swift             # ffmpeg process management + availability check
│   ├── LMStudioClient.swift            # HTTP client for local LLM
│   ├── MetadataService.swift           # AVFoundation metadata reading
│   ├── CSVLogger.swift                 # Low-quality CSV writer
│   └── DuplicateIndex.swift            # In-memory title+artist index
│
├── Infrastructure/
│   ├── Logger.swift                    # os.Logger + file logging
│   ├── NotificationManager.swift       # UNUserNotificationCenter
│   ├── Errors.swift                    # Typed error enums
│   └── Extensions/
│       ├── URL+Extensions.swift
│       ├── Process+Async.swift         # async wrapper for Process
│       └── FileManager+Extensions.swift
│
├── Resources/
│   └── default-config.json             # Bundled default configuration
│
└── Tests/
    ├── AudioTaskTests.swift
    ├── PDFTaskTests.swift
    ├── ConfigStoreTests.swift
    ├── TaskRouterTests.swift
    └── Mocks/
        ├── MockFileWatcher.swift
        └── MockLMStudioClient.swift
```

---

## Architectural Patterns

### 1. Menu Bar-Only App (No Dock Icon)

macOS menu bar apps use `LSUIElement = true` in Info.plist to suppress the dock icon. With SwiftUI on macOS 13+, `MenuBarExtra` is the first-class API:

```swift
@main
struct OhMyClawApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("Oh My Claw", systemImage: "arrow.down.doc") {
            MenuBarView()
                .environment(coordinator)
        }
        .menuBarExtraStyle(.window)  // popover-style panel
    }
}
```

**Key detail:** `.menuBarExtraStyle(.window)` gives a popover panel (richer UI with sliders, toggles). `.menuBarExtraStyle(.menu)` gives a standard dropdown menu. The popover style is recommended here because the app needs config editing controls.

### 2. Protocol-Based Task System (Extensibility)

The task system uses a protocol that enforces a consistent contract. Adding a new file type (e.g., images, videos) means adding a new struct — zero changes to existing code:

```swift
/// Every task module conforms to this protocol.
protocol FileTask: Sendable {
    /// Unique identifier for this task (e.g., "audio", "pdf")
    var id: String { get }

    /// Human-readable name shown in UI
    var displayName: String { get }

    /// Whether this task is currently enabled
    var isEnabled: Bool { get }

    /// Check if this task can handle the given file (by extension, UTI, etc.)
    func canHandle(file: URL) -> Bool

    /// Process the file through the full pipeline.
    /// Returns a result indicating what happened.
    func process(file: URL, config: AppConfig) async throws -> TaskResult
}
```

```swift
/// Registry that holds all known tasks.
final class TaskRegistry: @unchecked Sendable {
    private var tasks: [FileTask] = []

    func register(_ task: FileTask) {
        tasks.append(task)
    }

    func tasks(for file: URL) -> [FileTask] {
        tasks.filter { $0.isEnabled && $0.canHandle(file: file) }
    }
}
```

Registration happens once at app startup:

```swift
let registry = TaskRegistry()
registry.register(AudioTask())
registry.register(PDFTask())
// Future: registry.register(ImageTask())
```

### 3. Pipeline Pattern (Step-Based Processing)

Each task internally runs a series of pipeline steps. Steps are small, testable, and composable:

```swift
protocol PipelineStep: Sendable {
    associatedtype Input
    associatedtype Output

    func execute(_ input: Input) async throws -> Output
}
```

For the audio task, the pipeline is a linear chain with early exits:

```swift
struct AudioTask: FileTask {
    let id = "audio"
    let displayName = "Audio Organizer"
    var isEnabled: Bool = true

    private let metadataValidator = MetadataValidator()
    private let durationChecker = DurationChecker()
    private let duplicateDetector: DuplicateDetector
    private let qualityEvaluator = QualityEvaluator()
    private let converter: AIFFConverter

    func canHandle(file: URL) -> Bool {
        let audioExtensions: Set<String> = ["mp3", "wav", "flac", "aiff", "aac", "alac", "m4a"]
        return audioExtensions.contains(file.pathExtension.lowercased())
    }

    func process(file: URL, config: AppConfig) async throws -> TaskResult {
        // Step 1: Read metadata
        let metadata = try await MetadataService.read(from: file)

        // Step 2: Validate required fields
        guard metadataValidator.validate(metadata, required: config.audio.requiredFields) else {
            return .skipped(reason: "Missing metadata")
        }

        // Step 3: Check duration
        guard durationChecker.passes(metadata.duration, threshold: config.audio.minDuration) else {
            return .skipped(reason: "Too short (\(metadata.duration)s < \(config.audio.minDuration)s)")
        }

        // Step 4: Duplicate check
        if duplicateDetector.isDuplicate(title: metadata.title, artist: metadata.artist) {
            try FileManager.default.removeItem(at: file)
            return .duplicate(title: metadata.title, artist: metadata.artist)
        }
        duplicateDetector.register(title: metadata.title, artist: metadata.artist)

        // Step 5: Move to ~/Music
        let destination = try FileMover.move(file, to: .music)

        // Step 6: Evaluate quality and convert or archive
        let ranking = qualityEvaluator.rank(format: metadata.format, bitrate: metadata.bitrate, config: config.audio)

        if ranking.shouldConvert {
            try await converter.convert(destination, to: .aiff16bit)
            return .processed(action: "Converted to AIFF")
        } else {
            let lowQualityPath = try FileMover.moveToLowQuality(destination)
            try CSVLogger.append(metadata, to: lowQualityPath.deletingLastPathComponent())
            return .processed(action: "Moved to low_quality")
        }
    }
}
```

### 4. Swift Concurrency Model

The concurrency model uses three layers:

**Layer 1: Actor for shared mutable state**

```swift
@Observable
@MainActor
final class AppCoordinator {
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var activeConversions = 0
    private(set) var recentActivity: [ActivityEntry] = []

    private var fileWatcher: FileWatcher?
    private let taskRouter: TaskRouter
    private let configStore: ConfigStore

    func start() {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        fileWatcher = FileWatcher(path: FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Downloads"))
        fileWatcher?.onNewFile = { [weak self] url in
            Task { await self?.handleNewFile(url) }
        }
        fileWatcher?.start()
    }

    func pause() {
        isPaused = true
        fileWatcher?.stop()           // stop monitoring
        // in-flight tasks continue naturally — they hold their own Task references
    }

    func stop() {
        isRunning = false
        isPaused = false
        fileWatcher?.stop()
    }

    private func handleNewFile(_ url: URL) async {
        let tasks = taskRouter.route(file: url)
        for task in tasks {
            do {
                let config = configStore.current
                let result = try await task.process(file: url, config: config)
                addActivity(.init(task: task.displayName, file: url.lastPathComponent, result: result))
            } catch {
                addActivity(.init(task: task.displayName, file: url.lastPathComponent, error: error))
                NotificationManager.shared.postError(error, context: url.lastPathComponent)
            }
        }
    }
}
```

**Layer 2: Bounded concurrency for ffmpeg**

```swift
actor ConversionPool {
    private let maxConcurrent: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init() {
        self.maxConcurrent = ProcessInfo.processInfo.activeProcessorCount
    }

    func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        running += 1
    }

    func release() {
        running -= 1
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        }
    }
}

struct AIFFConverter {
    private let pool = ConversionPool()

    func convert(_ file: URL, to format: AudioFormat) async throws {
        await pool.acquire()
        defer { Task { await pool.release() } }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
        process.arguments = [
            "-i", file.path,
            "-f", "aiff",
            "-acodec", "pcm_s16be",  // 16-bit big-endian (AIFF standard)
            "-y",                     // overwrite
            file.deletingPathExtension().appendingPathExtension("aiff").path
        ]
        try await process.runAsync()  // Extension method
    }
}
```

**Layer 3: Async Process wrapper**

```swift
extension Process {
    func runAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ProcessError.nonZeroExit(process.terminationStatus))
                }
            }
            do {
                try self.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

### 5. File Watching with FSEvents

The recommended approach for macOS is `DispatchSource.makeFileSystemObjectSource` for single-directory monitoring, or the lower-level FSEvents API for recursive/batch monitoring:

```swift
final class FileWatcher: @unchecked Sendable {
    private let path: URL
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.ohmyclaw.filewatcher", qos: .utility)
    var onNewFile: ((URL) -> Void)?

    init(path: URL) {
        self.path = path
    }

    func start() {
        let fd = open(path.path, O_EVTONLY)
        guard fd >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,   // fires when directory contents change
            queue: queue
        )

        // Snapshot existing files to diff against
        var knownFiles = Set(currentFiles())

        source?.setEventHandler { [weak self] in
            guard let self else { return }
            let current = Set(self.currentFiles())
            let newFiles = current.subtracting(knownFiles)
            knownFiles = current

            for file in newFiles {
                // Debounce: wait for file to finish writing
                self.waitForStableSize(file) {
                    self.onNewFile?(file)
                }
            }
        }

        source?.setCancelHandler { close(fd) }
        source?.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func currentFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: path, includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        )) ?? []
    }

    private func waitForStableSize(_ url: URL, completion: @escaping () -> Void) {
        // Poll file size — when it stops changing for 1s, the download is complete
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let size1 = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            self.queue.asyncAfter(deadline: .now() + 1.0) {
                let size2 = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size1 == size2 && size2 > 0 {
                    completion()
                } else {
                    self.waitForStableSize(url, completion: completion)
                }
            }
        }
    }
}
```

**Why debounce matters:** Browsers write downloads progressively. Without waiting for stable file size, the pipeline would try to read incomplete files. The 1-second stability check is the standard pattern.

### 6. Configuration System

```swift
struct AppConfig: Codable, Sendable {
    var audio: AudioConfig
    var pdf: PDFConfig
    var general: GeneralConfig
}

struct AudioConfig: Codable, Sendable {
    var requiredFields: [String] = ["title", "artist", "album"]
    var minDuration: TimeInterval = 60
    var qualityCutoff: Int = 3        // ranking position
    var formatRanking: [FormatRank] = FormatRank.defaults
}

struct PDFConfig: Codable, Sendable {
    var lmStudioHost: String = "http://localhost:1234"
    var model: String = "default"
    var papersDestination: String = "~/Documents/Papers"
}

struct GeneralConfig: Codable, Sendable {
    var launchAtLogin: Bool = false
    var logLevel: String = "info"
}
```

```swift
@Observable
final class ConfigStore {
    private(set) var current: AppConfig
    private let fileURL: URL

    init() {
        // Config lives at ~/Library/Application Support/OhMyClaw/config.json
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let configDir = appSupport.appendingPathComponent("OhMyClaw")
        self.fileURL = configDir.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: fileURL),
           let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.current = config
        } else {
            // Load bundled default, copy to app support
            self.current = AppConfig.defaults
            try? self.save()
        }
    }

    func update(_ transform: (inout AppConfig) -> Void) throws {
        transform(&current)
        try save()
    }

    private func save() throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(current)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

### 7. State Management Between UI and Services

The pattern is `@Observable` + SwiftUI `environment`:

```
┌────────────┐   @Observable    ┌────────────────┐
│ MenuBarView │ ◄──────────────► │ AppCoordinator │
│  (SwiftUI)  │   environment   │   (@MainActor) │
└────────────┘                  └───────┬────────┘
                                        │ owns
                              ┌─────────┼─────────┐
                              ▼         ▼         ▼
                        ConfigStore  FileWatcher  TaskRouter
```

- `AppCoordinator` is `@MainActor` and `@Observable` — SwiftUI views automatically re-render when its properties change.
- Background work (file processing, ffmpeg) runs on cooperative thread pool via `async/await` — no manual `DispatchQueue` juggling.
- UI reads state directly from coordinator properties. UI actions call coordinator methods.

### 8. Error Handling Strategy

```swift
enum OhMyClawError: LocalizedError {
    case ffmpegNotFound
    case ffmpegFailed(exitCode: Int32, stderr: String)
    case metadataUnreadable(URL)
    case lmStudioUnreachable(String)
    case lmStudioError(String)
    case configCorrupted(URL)
    case fileMoveFailed(source: URL, destination: URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            "ffmpeg not found. Install via: brew install ffmpeg"
        case .ffmpegFailed(let code, let stderr):
            "ffmpeg exited with code \(code): \(stderr)"
        // ... etc
        }
    }
}
```

Errors surface through two channels:
1. **Notification banner** — user-facing, via `UNUserNotificationCenter`
2. **Log file** — detailed, via `os.Logger` + rotating file at `~/Library/Logs/OhMyClaw/`

### 9. Launch at Login (macOS 13+)

```swift
import ServiceManagement

struct LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() throws {
        if isEnabled {
            try SMAppService.mainApp.unregister()
        } else {
            try SMAppService.mainApp.register()
        }
    }
}
```

No helper app needed on macOS 13+ — `SMAppService` handles it natively.

---

## Data Flow

### Audio File Lifecycle

```
~/Downloads/song.flac
       │
       ▼
  [FileWatcher detects new file]
       │
       ▼
  [Debounce: wait for stable size]
       │
       ▼
  [TaskRouter: extension matches AudioTask]
       │
       ▼
  ┌─ MetadataValidator ──────────────────────────────┐
  │  Read title, artist, album via AVFoundation       │
  │  Missing required field? → SKIP (log reason)      │
  └──────────────────────────────────────┬────────────┘
                                         │ pass
  ┌─ DurationChecker ───────────────────▼────────────┐
  │  duration < config.minDuration? → SKIP            │
  └──────────────────────────────────────┬────────────┘
                                         │ pass
  ┌─ DuplicateDetector ─────────────────▼────────────┐
  │  title+artist already in index? → DELETE from     │
  │  Downloads (the version in ~/Music stays)         │
  └──────────────────────────────────────┬────────────┘
                                         │ unique
  ┌─ FileMover ─────────────────────────▼────────────┐
  │  Move file to ~/Music/                            │
  └──────────────────────────────────────┬────────────┘
                                         │
  ┌─ QualityEvaluator ──────────────────▼────────────┐
  │  Look up format in ranking                        │
  │  Position ≤ config.qualityCutoff?                 │
  ├─── YES ──────────────────┐                        │
  │                          ▼                        │
  │            ┌─ AIFFConverter ─────────┐            │
  │            │  Acquire semaphore slot  │            │
  │            │  ffmpeg → .aiff 16-bit   │            │
  │            │  Delete original         │            │
  │            │  Release semaphore       │            │
  │            └─────────────────────────┘            │
  ├─── NO ───────────────────┐                        │
  │                          ▼                        │
  │            ┌─ LowQualityArchiver ────┐            │
  │            │  Move to low_quality/    │            │
  │            │  Append row to CSV       │            │
  │            └─────────────────────────┘            │
  └───────────────────────────────────────────────────┘
```

### PDF File Lifecycle

```
~/Downloads/document.pdf
       │
       ▼
  [FileWatcher → TaskRouter → PDFTask]
       │
       ▼
  ┌─ ContentExtractor ──────────────────────────────┐
  │  Extract first N pages of text via PDFKit         │
  └──────────────────────────────────────┬────────────┘
                                         │
  ┌─ LLMClassifier ────────────────────▼────────────┐
  │  POST to LM Studio API (localhost:1234)           │
  │  Prompt: "Is this a scientific paper? ..."        │
  │  Parse response → { isPaper: Bool, confidence }   │
  │  LM Studio unreachable? → SKIP + notify           │
  └──────────────────────────────────────┬────────────┘
                                         │
  ┌─ PaperMover ───────────────────────▼────────────┐
  │  isPaper == true → move to ~/Documents/Papers     │
  │  isPaper == false → leave in Downloads (no-op)    │
  └───────────────────────────────────────────────────┘
```

---

## Build Order

Suggested implementation order based on dependency graph. Each phase produces a working (if incomplete) app:

```
Phase 0: Skeleton                              [~1 day]
├── Xcode project setup (macOS app, SwiftUI lifecycle)
├── Info.plist: LSUIElement = true
├── Empty MenuBarExtra with icon
└── Verify: icon shows in menu bar, no dock icon

Phase 1: Configuration                         [~1 day]
├── AppConfig / AudioConfig / PDFConfig models (Codable)
├── ConfigStore (load/save JSON)
├── Bundle default-config.json
└── Verify: config loads and round-trips to disk

Phase 2: File Watcher                          [~1 day]
├── FileWatcher (FSEvents, debounce)
├── Wire to AppCoordinator.start/stop/pause
└── Verify: new files detected, paused state stops events

Phase 3: Task System Core                      [~0.5 day]
├── FileTask protocol
├── TaskRegistry
├── TaskRouter
└── Verify: dummy task receives file events

Phase 4: Audio Pipeline                        [~3 days]
├── MetadataService (AVFoundation)
├── MetadataValidator step
├── DurationChecker step
├── DuplicateDetector (in-memory index)
├── FileMover (move to ~/Music)
├── QualityEvaluator (ranking lookup)
├── FFmpegService (availability check, auto-install prompt)
├── AIFFConverter + ConversionPool
├── CSVLogger (low-quality logging)
├── AudioTask (wires all steps together)
└── Verify: drop audio file in Downloads → appears in ~/Music as AIFF

Phase 5: PDF Pipeline                          [~1.5 days]
├── LMStudioClient (HTTP, health check)
├── ContentExtractor (PDFKit)
├── LLMClassifier
├── PaperMover
├── PDFTask
└── Verify: drop PDF in Downloads → classified and moved (or not)

Phase 6: Menu Bar UI                           [~1.5 days]
├── MenuBarView (on/off/pause toggles)
├── StatusView (recent activity feed)
├── ConfigEditorView (duration slider, quality cutoff, etc.)
└── Verify: controls work, state reflects in UI

Phase 7: Polish                                [~1.5 days]
├── NotificationManager (error + completion banners)
├── Logger (file-based rotating log)
├── LaunchAtLogin toggle
├── ffmpeg auto-install check
├── Edge cases: partial downloads, permission errors, disk full
└── Verify: app survives real-world usage for a day

Phase 8: Testing                               [~1 day]
├── Unit tests: each pipeline step in isolation
├── Integration test: full audio pipeline with fixture files
├── Integration test: PDF pipeline with mock LLM
└── Verify: CI-green test suite
```

**Total estimate: ~11–12 days** for a single developer, assuming familiarity with Swift/SwiftUI.

---

## Key Technical Decisions & Rationale

| Decision | Alternatives Considered | Why This Way |
|----------|------------------------|--------------|
| `@Observable` (macOS 14+) over `ObservableObject` | `ObservableObject` + `@Published` | Simpler syntax, less boilerplate, better performance (fine-grained observation). If macOS 13 needed, fall back to `ObservableObject`. |
| `MenuBarExtra` over `NSStatusItem` | Direct `NSStatusItem` + `NSPopover` | First-class SwiftUI API, less AppKit bridging code. Requires macOS 13+. |
| `actor` for `ConversionPool` over `DispatchSemaphore` | GCD semaphore, OperationQueue | Integrates with Swift Concurrency, no blocking threads, natural backpressure. |
| `DispatchSource` FSEvents over polling | Timer-based polling, `NSFilePresenter` | Immediate notification, low CPU, macOS-native. |
| Protocol-based tasks over subclassing | Inheritance hierarchy, enum-based dispatch | Composition over inheritance, easy to add tasks without touching existing code. |
| File-size debounce over `.crdownload` checks | Checking for temp file extensions | Works across all browsers and download managers, not dependent on browser internals. |
| `SMAppService` over `LSSharedFileList` | Legacy login item APIs | Modern API, macOS 13+, no helper app needed. |

---

## References

- Apple: [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) — SwiftUI menu bar API
- Apple: [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) — Login items
- Apple: [Dispatch Sources](https://developer.apple.com/documentation/dispatch/dispatchsource) — File system monitoring
- Apple: [AVAsset metadata](https://developer.apple.com/documentation/avfoundation/avasset) — Audio metadata reading
- Apple: [os.Logger](https://developer.apple.com/documentation/os/logger) — Unified logging
- Swift Evolution: [@Observable macro](https://github.com/apple/swift-evolution/blob/main/proposals/0395-observability.md)
