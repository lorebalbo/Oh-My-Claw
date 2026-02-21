# Phase 1: App Foundation & File Watching - Research

**Researched:** 2026-02-21
**Domain:** macOS Menu Bar App Shell, FSEvents File Monitoring, JSON Configuration, Structured Logging
**Confidence:** HIGH

## Summary

Phase 1 establishes the core foundation: a SwiftUI menu bar app (no Dock presence) using `MenuBarExtra`, an FSEvents-based file watcher for ~/Downloads with debounce and temp file filtering, a JSON configuration system at ~/Library/Application Support/OhMyClaw/, and structured JSON-lines logging with rotation. All components use Apple-native frameworks — no third-party dependencies are needed for this phase.

The key technical challenges are: (1) FSEvents fires before files are fully written, requiring debounce + file size stability checks, (2) macOS can throttle/terminate menu bar-only apps via App Nap, requiring explicit lifecycle management, and (3) the configuration system must validate user input yet fall back gracefully to defaults.

**Primary recommendation:** Use Swift Concurrency throughout (async/await, AsyncStream for FSEvents, actors for state isolation). This sets the pattern for all future phases.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- SF Symbol for the menu bar icon (system-native, will match macOS appearance)
- Minimal dropdown in Phase 1: toggle switch for monitoring on/off + Quit — nothing else
- Toggle style: a toggle/switch-style control in the menu (not a text label that changes)
- Monitoring auto-starts on app launch — no user action required to begin watching
- Config location: ~/Library/Application Support/OhMyClaw/config.json (standard macOS path)
- First-launch config: minimal keys only — hardcoded defaults fill in the rest
- Config structure: nested by feature area (e.g., `{ "audio": { ... }, "watcher": { ... } }`)
- Invalid config handling: fallback to defaults for bad values AND notify the user about the invalid config (both behaviors)
- Debounce: 3-5 seconds after file activity stops before processing
- File size stability check: yes — verify file size hasn't changed before handing off (on top of debounce)
- Ignore list: extended — .crdownload, .part, .tmp, .download, .partial, .downloading, plus hidden files (dotfiles)
- Existing files on launch: scan and process any matching files already in ~/Downloads when app starts
- Existing file processing: process all matching files in parallel (not sequentially)
- Watch directory: ~/Downloads only, hardcoded (not configurable)
- Subdirectories: top-level ~/Downloads only — no recursive scanning
- Disappeared files: if a file is removed/moved before processing completes, skip it and notify the user via macOS notification
- Log location: ~/Library/Logs/OhMyClaw/
- Log format: JSON lines (structured) — e.g., `{"ts": "...", "level": "info", "msg": "..."}`
- Rotation: rotate when log file reaches 10MB
- Retention: keep last 3 rotated log files (~30MB max total)
- Default verbosity: INFO level (operational events only — file detections, moves, errors)

### Claude's Discretion
- Specific SF Symbol choice for the menu bar icon
- Exact debounce timing within the 3-5 second range
- JSON lines field naming and structure details
- Internal architecture patterns (actors, services, etc.)

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| APP-01 | User can toggle the app on/off from the menu bar icon | MenuBarExtra with Toggle control, @Observable AppState for monitoring on/off |
| WATCH-01 | App monitors ~/Downloads in real-time using FSEvents | FSEventStreamCreate with kFSEventStreamCreateFlagFileEvents, wrapped in AsyncStream |
| WATCH-02 | Watcher debounces file events to avoid processing incomplete downloads | Per-file debounce timer (3s) + file size stability check (2 reads 500ms apart) |
| WATCH-03 | Watcher ignores temporary files (.crdownload, .part, .tmp, .download) | Extension allowlist + dotfile filter + extended temp extension blocklist |
| CFG-01 | App reads settings from external JSON config file | Codable AppConfig at ~/Library/Application Support/OhMyClaw/config.json, bundled defaults |
| INF-03 | All operations are logged to rotating log file | Custom JSON-lines file logger at ~/Library/Logs/OhMyClaw/, 10MB rotation, 3 file retention |
</phase_requirements>

## Standard Stack

### Core
| Library/Framework | Version | Purpose | Why Standard |
|---|---|---|---|
| Swift | 5.10+ | Primary language | Native macOS, strong concurrency model |
| SwiftUI | macOS 13+ | Menu bar UI | `MenuBarExtra` is the modern API for menu bar apps |
| Swift Concurrency | Built-in | Async patterns | AsyncStream for FSEvents, actors for state isolation |

### Supporting (System Frameworks)
| Library/Framework | Version | Purpose | When to Use |
|---|---|---|---|
| CoreServices (FSEvents) | System | File system monitoring | FSEventStreamCreate for ~/Downloads watching |
| Foundation | System | File management, JSON, Process | FileManager, JSONDecoder/Encoder, PropertyListSerialization |
| UserNotifications | System | Error/info notifications | UNUserNotificationCenter for disappeared file alerts, config errors |
| os (OSLog) | System | Console/system logging | Logger(subsystem:category:) for debug-level system logs alongside file logging |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FSEvents (CoreServices) | DispatchSource.makeFileSystemObjectSource | DispatchSource only monitors a single file descriptor, no per-file event details — FSEvents is better for directory monitoring |
| Custom JSON-lines logger | CocoaLumberjack / SwiftyBeaver | Adds third-party dependency for simple rotating file logging; custom solution is ~100 LOC |
| Codable JSON config | UserDefaults / plist | User decision: JSON config file, human-readable and externally editable |

## Architecture Patterns

### Recommended Project Structure (Phase 1 scope)
```
OhMyClaw/
├── OhMyClawApp.swift              # @main, MenuBarExtra setup
├── Info.plist                      # LSUIElement=true
│
├── App/
│   ├── AppCoordinator.swift        # Central actor coordinating services
│   └── AppState.swift              # @Observable app-wide state (isMonitoring, etc.)
│
├── UI/
│   └── MenuBarView.swift           # Toggle + Quit dropdown
│
├── Config/
│   ├── AppConfig.swift             # Top-level Codable config model (nested by feature)
│   └── ConfigStore.swift           # Load/save/validate, bundled defaults fallback
│
├── Core/
│   ├── FileWatcher.swift           # FSEvents wrapper → AsyncStream<FileEvent>
│   └── Protocols/
│       └── FileTask.swift          # Protocol for future task modules
│
├── Infrastructure/
│   ├── Logger.swift                # JSON-lines file logger with rotation
│   ├── NotificationManager.swift   # UNUserNotificationCenter wrapper
│   └── Extensions/
│       └── URL+Extensions.swift
│
├── Resources/
│   └── default-config.json         # Bundled default configuration
│
└── Tests/
    ├── ConfigStoreTests.swift
    └── FileWatcherTests.swift
```

### Pattern 1: Menu Bar App with @Observable State
**What:** SwiftUI `MenuBarExtra` + `@Observable` `AppState` class for reactive UI updates.
**When to use:** All menu bar interactions that need to reflect state changes.

```swift
@main
struct OhMyClawApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Oh My Claw", systemImage: "arrow.down.doc") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.menu)  // Simple dropdown for Phase 1
    }
}

@Observable
final class AppState {
    var isMonitoring: Bool = true  // auto-starts on launch
}
```

### Pattern 2: FSEvents as AsyncStream
**What:** Wrap the C-level FSEvents API in an `AsyncStream<FileEvent>` for clean Swift Concurrency integration.
**When to use:** FileWatcher implementation.

```swift
struct FileEvent {
    let path: String
    let flags: FSEventStreamEventFlags
}

func startWatching(directory: String) -> AsyncStream<FileEvent> {
    AsyncStream { continuation in
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            for i in 0..<numEvents {
                continuation.yield(FileEvent(path: paths[i], flags: eventFlags[i]))
            }
        }
        var context = FSEventStreamContext(/* ... */)
        let stream = FSEventStreamCreate(
            nil, callback, &context,
            [directory as CFString] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // 1s latency for batching
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )!
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "com.ohmyclaw.fsevents"))
        FSEventStreamStart(stream)
        continuation.onTermination = { _ in
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
```

### Pattern 3: Actor-Based Coordinator
**What:** Use a Swift `actor` for the AppCoordinator to serialize state access and coordinate services.
**When to use:** Central orchestration of FileWatcher + ConfigStore + Logger.

```swift
actor AppCoordinator {
    private let configStore: ConfigStore
    private let fileWatcher: FileWatcher
    private let logger: AppLogger
    private var isMonitoring = true

    func start() async {
        await configStore.load()
        logger.info("App started, monitoring ~/Downloads")

        // Scan existing files first
        await processExistingFiles()

        // Then start watching for new files
        for await event in fileWatcher.events {
            guard isMonitoring else { continue }
            await handleFileEvent(event)
        }
    }

    func toggleMonitoring() {
        isMonitoring.toggle()
    }
}
```

### Pattern 4: Debounce + Stability Check
**What:** Per-file debounce timer that resets on each event, followed by a file size stability check before handoff.
**When to use:** FileWatcher before dispatching to task modules.

```swift
// Debounce: 3 seconds after last event for a given path
// Stability: Two consecutive size reads 500ms apart must match
actor FileDebouncer {
    private var pendingFiles: [String: Task<Void, Never>] = [:]

    func debounce(path: String, action: @escaping () async -> Void) {
        pendingFiles[path]?.cancel()
        pendingFiles[path] = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            // File size stability check
            guard await isFileStable(path: path) else { return }

            await action()
            pendingFiles[path] = nil
        }
    }

    private func isFileStable(path: String) async -> Bool {
        guard let size1 = fileSize(path) else { return false }
        try? await Task.sleep(for: .milliseconds(500))
        guard let size2 = fileSize(path) else { return false }
        return size1 == size2
    }
}
```

### Anti-Patterns to Avoid
- **Polling instead of FSEvents:** Causes unnecessary CPU usage. Use event-driven FSEvents.
- **DispatchSource for directory monitoring:** Only monitors a single file descriptor, doesn't provide per-file event details.
- **Blocking the main thread with file operations:** All file I/O should be async.
- **Writing to the watched directory:** Causes infinite event loops.
- **Using NSStatusItem directly:** Use MenuBarExtra — it's the modern SwiftUI API.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Menu bar presence | Custom NSStatusItem + NSMenu | SwiftUI MenuBarExtra | First-class API since macOS 13, handles lifecycle |
| JSON serialization | Manual JSON building/parsing | Codable + JSONDecoder/Encoder | Type-safe, exhaustive, compiler-checked |
| Directory paths | Hardcoded ~/Library/... strings | FileManager.urls(for: .applicationSupportDirectory) | Handles sandboxing, locale, edge cases |
| Notification delivery | Custom alert/popup system | UNUserNotificationCenter | Native macOS notifications, proper system integration |
| File existence checks | Custom stat() wrappers | FileManager.isReadableFile(atPath:) | Handles permissions, symlinks correctly |

**Key insight:** Phase 1 uses 100% Apple-native frameworks. Zero third-party dependencies keeps the build simple and the app lightweight.

## Common Pitfalls

### Pitfall 1: FSEvents Fires Before File Is Fully Written
**What goes wrong:** FSEvents fires the instant a file appears in ~/Downloads, but the file is still being written (Safari, Chrome, AirDrop).
**Why it happens:** Browsers write in stages: create temp file → write data → rename. FSEvents fires at each stage.
**How to avoid:** Extended temp file ignore list + 3s debounce + file size stability check (2 reads 500ms apart).
**Warning signs:** Truncated files, "file in use" errors, intermittent read failures.

### Pitfall 2: .DS_Store and Spotlight Metadata Noise
**What goes wrong:** FSEvents fires for .DS_Store, .localized, Spotlight metadata files.
**Why it happens:** macOS generates filesystem metadata constantly.
**How to avoid:** Ignore all dotfiles. Only process files matching known audio/PDF extensions. Never write to the watched directory.
**Warning signs:** High idle CPU, log spam, event loops.

### Pitfall 3: Menu Bar App Killed by App Nap / Memory Pressure
**What goes wrong:** macOS kills or throttles the menu bar-only app because it has no visible UI.
**Why it happens:** macOS treats background-only apps as low-priority.
**How to avoid:** `ProcessInfo.processInfo.automaticTerminationSupportEnabled = false`, `NSSupportsAutomaticTermination = NO` in Info.plist, disable sudden termination while processing.
**Warning signs:** Menu bar icon disappears, file watcher stops after sleep/wake.

### Pitfall 4: Config File Race Conditions
**What goes wrong:** Reading config while the user is editing it externally produces partial/corrupted JSON.
**Why it happens:** File writes aren't atomic by default.
**How to avoid:** Read the entire file atomically via `Data(contentsOf:)`. Validate with JSONDecoder — if it fails, keep previous valid config and log a warning.
**Warning signs:** Sporadic config parse failures, settings resetting unexpectedly.

### Pitfall 5: Log File Growth Without Rotation
**What goes wrong:** JSON-lines log file grows unbounded, consuming disk space.
**Why it happens:** No rotation logic, or rotation only checked at app launch.
**How to avoid:** Check file size before each write. When ≥10MB, rotate (rename current → .1, delete .3). Keep at most 3 rotated files.
**Warning signs:** Log directory consuming hundreds of MB, slow log writes.

## Code Examples

### JSON-Lines Rotating Logger
```swift
final class AppLogger: Sendable {
    private let logDirectory: URL
    private let maxFileSize: Int64 = 10 * 1024 * 1024  // 10MB
    private let maxRotatedFiles = 3
    private let queue = DispatchQueue(label: "com.ohmyclaw.logger")

    enum Level: String, Codable {
        case debug, info, warn, error
    }

    struct LogEntry: Codable {
        let ts: String
        let level: String
        let msg: String
        let ctx: [String: String]?
    }

    func log(_ level: Level, _ message: String, context: [String: String]? = nil) {
        queue.async {
            let entry = LogEntry(
                ts: ISO8601DateFormatter().string(from: Date()),
                level: level.rawValue,
                msg: message,
                ctx: context
            )
            guard let data = try? JSONEncoder().encode(entry),
                  var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"

            self.rotateIfNeeded()
            self.appendToFile(line)
        }
    }
}
```

### Config Loading with Fallback + Notification
```swift
@Observable
final class ConfigStore {
    private(set) var config: AppConfig
    private let configURL: URL
    private let defaults: AppConfig

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("OhMyClaw")
        self.configURL = appSupport.appendingPathComponent("config.json")
        self.defaults = AppConfig.defaults
        self.config = defaults
    }

    func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            // First launch: create config with minimal keys
            save(defaults)
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            config = defaults
            // Notify user about invalid config
            NotificationManager.shared.notify(
                title: "Config Error",
                body: "Invalid config file — using defaults. \(error.localizedDescription)"
            )
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| NSStatusItem + NSMenu | SwiftUI MenuBarExtra | macOS 13 (2022) | Declarative, type-safe menu bar apps |
| NSApplication delegate lifecycle | @main App struct with Scene | SwiftUI lifecycle (2020+) | Simpler app setup |
| SMLoginItemSetEnabled + helper app | SMAppService.mainApp | macOS 13 (2022) | One-line Login Item, no helper app |
| NSUserDefaults / plist | Codable JSON (user decision) | N/A | User preference for external JSON config |
| os_log C API | Swift Logger struct | macOS 11+ (2020) | Cleaner API, string interpolation support |

## Open Questions

1. **Sandboxing vs. non-sandboxed distribution**
   - What we know: Non-App Store distribution, so sandboxing is optional. ~/Downloads access without sandbox is straightforward.
   - What's unclear: Whether to enable App Sandbox for security best practices.
   - Recommendation: Skip sandboxing for v1 (direct distribution) — simplifies file access and ffmpeg execution. Document as a v2 consideration.

2. **Exact SF Symbol for menu bar icon**
   - What we know: Must be an SF Symbol, system-native appearance.
   - What's unclear: Which symbol best represents "file organizer."
   - Recommendation: `arrow.down.doc` (document with down arrow — represents downloads being organized) or `tray.and.arrow.down` (tray receiving items).

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — MenuBarExtra, FSEvents, SMAppService, Logger
- Project research files — STACK.md, ARCHITECTURE.md, PITFALLS.md (researched 2026-02-21)

### Secondary (MEDIUM confidence)
- Swift Concurrency patterns — AsyncStream, actor isolation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all Apple-native frameworks, well-documented APIs
- Architecture: HIGH — established patterns from project architecture research
- Pitfalls: HIGH — well-known macOS development gotchas, documented in project research

**Research date:** 2026-02-21
**Valid until:** 2026-06-21 (stable APIs, no expected breaking changes)
