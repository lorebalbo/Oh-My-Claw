# Phase 6: Resilience & Polish — Research

**Researched:** 2026-02-22

## 1. macOS Local Notifications (UNUserNotificationCenter)

### Current State

`NotificationManager` already wraps `UNUserNotificationCenter`. It requests authorization with `.alert` and `.sound` options at init time, posts notifications with `UNMutableNotificationContent`, and uses `trigger: nil` for immediate delivery. Two convenience methods exist: `notifyConfigError(_:)` and `notifyFileDisappeared(filename:)`.

### How UNUserNotificationCenter Works for Menu Bar Apps

**Authorization**. `UNUserNotificationCenter.current().requestAuthorization(options:)` is asynchronous. On first call, macOS shows a permission prompt. Subsequent calls return the cached decision. The existing code already does this in `NotificationManager.init()`.

**LSUIElement apps**. Oh My Claw sets `LSUIElement = true` in Info.plist (agent app with no dock icon). UNUserNotificationCenter works normally in LSUIElement apps — no special handling needed. Notifications appear in Notification Center and banner area as expected.

**Notification content fields**:
- `title` — bold headline
- `subtitle` — optional second line (useful for error type)
- `body` — detail text
- `sound` — `UNNotificationSound.default` plays the system notification sound
- `threadIdentifier` — groups related notifications in Notification Center (useful for batching by error type)
- `categoryIdentifier` — allows actionable notifications (not needed for Phase 6)

**Notification identifier semantics**. Posting a new `UNNotificationRequest` with the same `identifier` as an existing pending notification **replaces** it. This is the key mechanism for implementing batching: post a notification with a stable identifier (e.g., `"error-batch-audio"`), then update it with an incremented count as more errors arrive.

**Delivery when app is in foreground**. By default, UNUserNotificationCenter does **not** show banners when the app is in the foreground. To enable this, implement `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)` and call the completion handler with `[.banner, .sound]`. Since Oh My Claw is an LSUIElement app, the "foreground" concept is minimal, but the delegate should still be set to ensure banner display when the menu bar popover is open.

```swift
// Delegate to allow banners while app is "foreground"
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
```

**Setup**: Call `center.delegate = self` in `NotificationManager.init()`.

### Sound Configuration

`UNNotificationSound.default` plays the system default notification sound. This matches the user decision ("default macOS notification sound"). No custom sound file needed.

### Notification Replacement for Batching

When multiple errors arrive within a batching window, post successive notifications with the same `identifier`:

```swift
// First error:
content.body = "Failed to convert song.mp3: ffmpeg error"
request.identifier = "error-batch-audio"

// Second error (1.5s later):
content.body = "2 audio files failed processing"
request.identifier = "error-batch-audio"  // replaces the first
```

This leverages UNUserNotificationCenter's built-in replacement behavior — no need to manually remove the previous notification.

### Sandboxing Considerations

Oh My Claw does not appear to be sandboxed (no entitlements file visible, and it accesses `~/Downloads` and `~/Music` directly). UNUserNotificationCenter works for both sandboxed and non-sandboxed apps. The only requirement is that the app requests authorization, which is already done.

---

## 2. Error Batching & Cooldown Patterns

### Error Categorization Taxonomy

Proposed categories based on the codebase's error paths:

| Category | Source | Example |
|----------|--------|---------|
| `audioConversion` | `AudioTask.process()` → ffmpeg failure | "ffmpeg conversion failed: exit code 1" |
| `audioMetadata` | `AudioTask.process()` → metadata read failure | "Failed to read metadata" |
| `audioFileMove` | `AudioTask.moveFile()` → permission denied | "Permission denied moving audio file" |
| `pdfClassification` | `PDFTask.process()` → LM Studio error | "LM Studio classification failed" |
| `configReload` | `ConfigStore` → invalid JSON | "Failed to parse config.json" |
| `fileDisappeared` | `AppCoordinator` event loop | "File removed before processing" |
| `general` | Catch-all | Any uncategorized error |

### Actor-Based Error Collector Design

An `ErrorCollector` actor collects errors, batches rapid ones, and enforces per-category cooldowns:

```swift
actor ErrorCollector {
    /// Errors buffered within the current batching window, grouped by category.
    private var pendingErrors: [ErrorCategory: [ErrorInfo]] = [:]
    
    /// Timestamp of last notification per category (for cooldown).
    private var lastNotified: [ErrorCategory: Date] = [:]
    
    /// Active batching timers per category.
    private var batchTimers: [ErrorCategory: Task<Void, Never>] = [:]

    private let batchWindow: TimeInterval = 3.0      // seconds to wait for more errors
    private let cooldownWindow: TimeInterval = 300.0  // 5 minutes between same error type

    func report(category: ErrorCategory, file: String, message: String) {
        // Check cooldown
        if let lastTime = lastNotified[category],
           Date().timeIntervalSince(lastTime) < cooldownWindow {
            return  // Suppressed by cooldown
        }

        // Accumulate
        let info = ErrorInfo(file: file, message: message, timestamp: Date())
        pendingErrors[category, default: []].append(info)

        // Reset or start batch timer
        batchTimers[category]?.cancel()
        batchTimers[category] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.0))
            guard !Task.isCancelled else { return }
            await self?.flushCategory(category)
        }
    }

    private func flushCategory(_ category: ErrorCategory) {
        guard let errors = pendingErrors.removeValue(forKey: category),
              !errors.isEmpty else { return }
        batchTimers.removeValue(forKey: category)
        lastNotified[category] = Date()

        // Build notification
        if errors.count == 1 {
            let e = errors[0]
            NotificationManager.shared.notify(
                title: "Oh My Claw — Error",
                body: "\(e.file): \(e.message)",
                identifier: "error-\(category.rawValue)"
            )
        } else {
            NotificationManager.shared.notify(
                title: "Oh My Claw — \(errors.count) Errors",
                body: "\(errors.count) \(category.displayName) errors occurred",
                identifier: "error-\(category.rawValue)"
            )
        }
    }
}
```

### Batching Window: 3 Seconds

A 3-second batching window balances responsiveness (user isn't waiting long) with grouping efficiency (enough to batch a burst of ffmpeg failures or a corrupt ZIP extraction that triggers many file events).

### Cooldown Window: 5 Minutes

Per the user decision, same-category errors should be suppressed after a notification to prevent spam. 5 minutes (300 seconds) is reasonable — long enough to avoid notification storms from a persistent error (e.g., LM Studio down), short enough that the user gets re-notified if the issue persists across different work sessions.

### Cooldown Edge Cases

- **Different files, same category**: Still cooldown. "3 audio files failed" → 5 min cooldown → next batch reports again.
- **Config errors**: These should bypass cooldown since they're user-initiated (user edited the file). Use a separate `configReload` category with no cooldown, or a short 10-second cooldown.
- **First error after app launch**: No cooldown — always notify immediately.

---

## 3. Config File Watching (FSEvents / DispatchSource)

### Approach: DispatchSource File-Level Watcher

For watching a single known file (config.json in Application Support), `DispatchSource.makeFileSystemObjectSource` is more appropriate than FSEvents directory monitoring. It watches a specific file descriptor for changes.

```swift
import Foundation

final class ConfigFileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.ohmyclaw.config-watcher", qos: .utility)
    private var fileDescriptor: Int32 = -1

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func start(onChange: @escaping () -> Void) {
        fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],   // covers atomic saves
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            
            if flags.contains(.delete) || flags.contains(.rename) {
                // File was replaced (atomic save). Re-open the new file.
                self.restart(onChange: onChange)
            } else {
                onChange()
            }
        }

        source.setCancelHandler { [fd = fileDescriptor] in
            close(fd)
        }

        source.resume()
        self.source = source
    }

    /// Re-open the file descriptor after an atomic save replaces the inode.
    private func restart(onChange: @escaping () -> Void) {
        source?.cancel()
        source = nil
        // Brief delay for the new file to be fully written
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.start(onChange: onChange)
        }
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
```

### Handling Atomic Saves (Critical)

Most text editors (Vim, VS Code, nano, Sublime Text, Xcode) perform **atomic saves**: they write to a temporary file, then rename it to replace the original. This means:

1. The original inode is **deleted** (or unlinked)
2. A new file is created at the same path with a **new inode**

Since `DispatchSource.makeFileSystemObjectSource` watches a file descriptor (which is tied to an inode), the watcher goes stale after an atomic save. The solution:

- Watch for `.delete` and `.rename` events in the event mask
- When these fire, close the old file descriptor, wait briefly (100ms), then re-open and re-attach the watcher to the new inode
- This "restart on replace" pattern is the standard approach

### Alternative: Watch the Parent Directory

An alternative that avoids the inode problem is to watch the **directory** containing config.json with FSEvents and filter for the config filename:

```swift
// Watch ~/Library/Application Support/OhMyClaw/ with FSEvents
// Filter events to only config.json
```

This is simpler (no inode re-tracking) but noisier. Given that the Application Support directory should have minimal activity, this is also viable. However, the DispatchSource approach is more precise and preferred.

### Debounce for Config Reload

Text editors may trigger multiple write events for a single save (especially editors that write in stages). Add a short debounce (500ms) before reading the config:

```swift
private var reloadTask: Task<Void, Never>?

private func scheduleReload() {
    reloadTask?.cancel()
    reloadTask = Task {
        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled else { return }
        await configStore.load()
    }
}
```

### Integration with ConfigStore

`ConfigStore` currently has `load()` and `save(_:)`. For hot-reload:

1. `load()` already handles invalid JSON (falls back to current config per user decision — though currently it falls back to defaults; this needs adjustment)
2. Add a method that loads and **compares** the new config to the old one, only updating if different
3. On successful reload, post a notification
4. On invalid JSON, keep old config active and notify the user

```swift
func reload() -> Bool {
    let oldConfig = config
    // ... decode new config from disk ...
    if newConfig != oldConfig {
        config = newConfig
        return true  // changed
    }
    return false  // no change
}
```

### Watching from AppCoordinator

The `ConfigFileWatcher` should be owned by `AppCoordinator`, which:
1. Starts the watcher in `start()`
2. On change callback → calls `configStore.reload()`
3. If reload succeeds and config changed → log + notify "Config reloaded"
4. If reload fails → log + notify "Invalid config, keeping previous"
5. New config applies only to future files (in-flight tasks already captured their config values via value-type copies)

---

## 4. Sleep/Wake Recovery

### NSWorkspace Sleep/Wake Notifications

macOS posts workspace notifications for power events:

```swift
// Notification names
NSWorkspace.willSleepNotification    // system is about to sleep
NSWorkspace.didWakeNotification      // system just woke up
```

Subscribe via `NSWorkspace.shared.notificationCenter` (NOT `NotificationCenter.default`):

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    self, selector: #selector(handleWillSleep),
    name: NSWorkspace.willSleepNotification, object: nil
)
NSWorkspace.shared.notificationCenter.addObserver(
    self, selector: #selector(handleDidWake),
    name: NSWorkspace.didWakeNotification, object: nil
)
```

### Modern Async/Notification Approach

Since the codebase uses Swift concurrency throughout, use the `notifications(named:)` async sequence:

```swift
func observeSleepWake() {
    Task { @MainActor in
        let center = NSWorkspace.shared.notificationCenter
        
        // Will Sleep
        Task {
            for await _ in center.notifications(named: NSWorkspace.willSleepNotification) {
                await handleWillSleep()
            }
        }
        
        // Did Wake
        Task {
            for await _ in center.notifications(named: NSWorkspace.didWakeNotification) {
                await handleDidWake()
            }
        }
    }
}
```

### Will Sleep Handler

When the system sleeps, in-flight ffmpeg processes may be killed (SIGKILL or SIGSTOP). The handler should:

1. **Cancel the event loop task** — stop processing new files
2. **Cancel in-flight ffmpeg processes** — call `Process.terminate()` on running conversions. Since ffmpeg writes to a temp file (UUID-prefixed), the temp file remains as garbage. The source file in `~/Downloads` is untouched until conversion succeeds.
3. **Stop the FSEvents stream** — `FileWatcher.stop()` invalidates and releases the stream
4. **Cancel the config file watcher** — stop monitoring config changes during sleep

```swift
func handleWillSleep() async {
    AppLogger.shared.info("System will sleep — tearing down watchers")
    
    // Cancel event loop (stops processing new events)
    eventLoopTask?.cancel()
    eventLoopTask = nil
    
    // Stop FSEvents stream
    fileWatcher?.stop()
    fileWatcher = nil
    
    // Stop config file watcher
    configFileWatcher?.stop()
    
    // Note: in-flight ffmpeg processes will be killed by the OS on sleep.
    // Their temp files remain in /tmp — macOS cleans these periodically.
    // Source files are still in ~/Downloads, so they'll be re-detected on wake.
}
```

### Did Wake Handler

On wake, restore all monitoring:

1. **Re-create and start a new FSEvents stream** — `FileWatcher` needs a new `start()` call. The existing `FileWatcher.start()` creates a brand-new `FSEventStreamRef`, so calling `startMonitoring()` achieves this.
2. **Full re-scan of ~/Downloads** — `FileWatcher.scanExistingFiles()` already emits existing files. This catches files that arrived during sleep AND files whose ffmpeg conversion was interrupted (they're still in ~/Downloads since the source isn't deleted until conversion succeeds).
3. **Restart the event processing loop** — `startMonitoring()` creates a new `eventLoopTask`
4. **Restart config file watcher** — begin watching config.json again

```swift
func handleDidWake() async {
    AppLogger.shared.info("System woke — re-establishing monitoring")
    
    // Clean up any orphaned temp files from interrupted conversions
    cleanupInterruptedConversions()
    
    // Only restart if monitoring was enabled before sleep
    guard appState.isMonitoring else { return }
    
    // Restart everything
    await startMonitoring()        // re-creates FileWatcher + event loop + scans existing files
    startConfigFileWatcher()       // re-creates config file watcher
}
```

### Handling Interrupted ffmpeg Processes

The existing `FFmpegConverter.convert()` writes output to a temp file (`/tmp/UUID.aiff`), then atomically moves it to the destination. If ffmpeg is killed by sleep:

- **Temp file**: Orphaned in `/tmp`. Harmless — macOS cleans `/tmp` periodically. Optionally, clean up UUID-prefixed `.aiff` files in the temp directory on wake.
- **Source file**: Still in `~/Downloads` untouched. The re-scan on wake will pick it up and re-process it from scratch.
- **Conversion pool slot**: The actor's `inFlight` count may be stale if the task was cancelled mid-flight. Since `startMonitoring()` creates a fresh `FileWatcher`, and `ConversionPool` slots are managed per-conversion, this should self-correct. However, if the `ConversionPool` actor persists across sleep/wake cycles, its state may be inconsistent. Best to create a fresh `ConversionPool` on wake, or add a `reset()` method.

### Process Tracking for Cancellation

The current `FFmpegConverter.convert()` creates a `Process` locally inside the function. To cancel in-flight conversions on sleep, we'd need to track running processes. Options:

1. **Track processes in ConversionPool** — the pool already manages concurrency; add process registration:
   ```swift
   actor ConversionPool {
       private var runningProcesses: [UUID: Process] = [:]
       
       func register(id: UUID, process: Process) {
           runningProcesses[id] = process
       }
       
       func terminateAll() {
           for (_, process) in runningProcesses {
               if process.isRunning { process.terminate() }
           }
           runningProcesses.removeAll()
       }
   }
   ```

2. **Let the OS handle it** — on sleep, the OS suspends/kills processes anyway. On wake, the `Task` wrapping the conversion will be cancelled (since `eventLoopTask` was cancelled). The continuation may never resume, but since we cancel the parent task, this is acceptable. The source file remains in ~/Downloads and will be re-detected.

**Recommended**: Option 2 (let the OS handle it) is simpler and sufficient. The cancelled `eventLoopTask` cascades cancellation to in-flight task processing. The re-scan on wake handles re-detection.

### Silent Recovery

Per user decision, no notification on wake recovery. Just log it:

```swift
AppLogger.shared.info("Monitoring resumed after sleep/wake")
```

---

## 5. Integration Points with Existing Codebase

### 5.1 NotificationManager (INF-02: Error Notifications)

**Current state**: `NotificationManager` is a `Sendable` singleton with `notify(title:body:identifier:)`, `notifyConfigError(_:)`, and `notifyFileDisappeared(filename:)`. Already requests authorization and uses `.default` sound.

**Changes needed**:
1. Add `UNUserNotificationCenterDelegate` conformance to show banners when the menu popover is open
2. The existing `notify()` method is sufficient as the low-level API — `ErrorCollector` will call it
3. Consider adding `threadIdentifier` to group notifications by error category in Notification Center

### 5.2 AppCoordinator (Central Orchestration)

**Current state**: Owns `ConfigStore`, `FileWatcher`, event loop `Task`, health polling `Task`, and all `FileTask` instances. Has `start()`, `startMonitoring()`, `stopMonitoring()`, `toggleMonitoring(_:)`.

**Changes needed**:
1. **Sleep/wake observers** — Subscribe to `NSWorkspace.willSleepNotification` and `.didWakeNotification` in `start()`
2. **Config file watcher** — Own a `ConfigFileWatcher` instance, start it alongside other services
3. **Error collector** — Own an `ErrorCollector` actor, pass it to tasks or intercept errors in the event loop
4. **Sleep handler** — Call `stopMonitoring()` + stop config watcher
5. **Wake handler** — Call `startMonitoring()` (existing method already creates new watcher + scans + starts event loop) + restart config watcher
6. **Error routing in event loop** — The event loop already has `catch` blocks and checks for `.error` results. Wire these through `ErrorCollector` instead of (or in addition to) just logging

**Event loop integration point** ([AppCoordinator.swift](OhMyClaw/App/AppCoordinator.swift#L133-L173)):
```swift
// Current: just logs errors
case .error(let description):
    AppLogger.shared.error("Processing error", ...)

// Phase 6: also report to error collector
case .error(let description):
    AppLogger.shared.error("Processing error", ...)
    await errorCollector.report(
        category: task.errorCategory,  // new property on FileTask
        file: fileURL.lastPathComponent,
        message: description
    )
```

And the catch block:
```swift
} catch {
    AppLogger.shared.error("Task failed", ...)
    await errorCollector.report(
        category: .general,
        file: fileURL.lastPathComponent,
        message: error.localizedDescription
    )
}
```

### 5.3 ConfigStore (CFG-05: Hot Reload)

**Current state**: `@MainActor @Observable`, has `load()` and `save(_:)`. `load()` reads from disk, decodes, validates. On invalid config, falls back to **defaults** (not previous config).

**Changes needed**:
1. **`reload()` method** — Similar to `load()` but on invalid config, keeps the **current** config active instead of falling back to defaults (per user decision)
2. **Change detection** — Compare decoded config to current config using `Equatable` conformance (already implemented on `AppConfig`)
3. **Expose the config file URL** — Currently `configURL` is private. Expose it (or expose a method) so `AppCoordinator` can create a `ConfigFileWatcher` pointing at it
4. **Thread safety** — `ConfigStore` is `@MainActor`, so `reload()` runs on the main actor. The config file watcher callback runs on a background queue, so it must dispatch to `@MainActor` to call `reload()`

**In-flight task safety**: `AudioTask` and `PDFTask` are `struct`s that capture config values at creation time (value types). When `ConfigStore.config` changes, the `tasks` array in `AppCoordinator` still holds the old struct values. To apply new config, `AppCoordinator` must rebuild the tasks array. However, per the user decision, in-flight tasks keep old config. Since the event loop processes files sequentially (one `for await` iteration at a time), rebuilding tasks between iterations is safe — the currently-executing task call has already captured its config.

### 5.4 FileWatcher (INF-04: Sleep/Wake Recovery)

**Current state**: Creates an FSEventStreamRef, starts it on a DispatchQueue. Has `start()`, `stop()`, `scanExistingFiles()`. The `AsyncStream` continuation is set up in `init()`.

**Changes needed**:
1. The current `stop()` properly cleans up (stops, invalidates, releases the stream, cancels debouncer). This is sufficient for sleep teardown.
2. **Issue**: The `AsyncStream` continuation is created once in `init()`. After `stop()` is called, `continuation.onTermination` fires and calls `stop()` again (harmless but wasteful). More importantly, if we want to **reuse** the same `FileWatcher.events` stream after sleep/wake, we can't — `AsyncStream` continuations are single-use.
3. **Solution**: Create a **new** `FileWatcher` instance on wake (which `startMonitoring()` already does — it creates `let watcher = FileWatcher(...)`). The old instance is released. The new event loop task iterates over the new watcher's events. This works cleanly with the current architecture.

### 5.5 FileTask Protocol & Task Instances

**Current state**: `AudioTask` and `PDFTask` conform to `FileTask`. They're structs with immutable config captured at creation.

**Changes needed**:
1. Optionally add an `errorCategory` property to `FileTask` protocol for error routing:
   ```swift
   protocol FileTask: Sendable {
       var errorCategory: ErrorCategory { get }
       // ... existing ...
   }
   ```
   Or determine category in `AppCoordinator` based on `task.id`.

### 5.6 AppState

**Current state**: Observable state with `isMonitoring`, `ffmpegAvailable`, `lmStudioAvailable`.

**Changes needed (minimal)**:
1. Potentially add a `lastConfigReload: Date?` for UI display
2. Track whether monitoring is paused due to sleep (to distinguish "user disabled" from "sleeping") — needed so wake handler only resumes if monitoring was enabled before sleep

### 5.7 MenuBarView (Config Changes from UI)

**Current state**: Has a monitoring toggle. Config changes from the UI go through `AppCoordinator.toggleMonitoring(_:)`.

**Phase 5 may add more config controls in the menu bar UI**. When the user changes config from the UI, `ConfigStore.save(_:)` writes to disk. The config file watcher will detect this write and trigger a reload. To avoid a redundant reload (UI already applied the change), either:
- Skip reload if the decoded config equals the current config (change detection via `Equatable`)
- Or add a "suppress next reload" flag after programmatic saves

The `Equatable` check is simpler and more robust.

---

## 6. Key Risks & Mitigations

### Risk 1: DispatchSource Inode Staleness After Atomic Save

**Risk**: Text editors (Vim, VS Code, Sublime) perform atomic saves that replace the file inode. The DispatchSource watches the old inode and stops receiving events.

**Mitigation**: Watch for `.delete` and `.rename` flags in the DispatchSource event mask. On these events, close the old file descriptor and re-open the new file. Add a 100ms delay before re-opening to ensure the new file is fully written. This is a well-known pattern used by many file-watching libraries.

### Risk 2: Notification Permission Denied

**Risk**: User denies notification permission on first prompt. All error notifications silently fail.

**Mitigation**: Check authorization status before posting. If denied, log a warning at app startup. Consider showing a status indicator in the menu bar UI. The existing code silently fails on denied permission (no crash, just no notifications) which is acceptable degraded behavior.

### Risk 3: Rapid Config Edits Causing Thrashing

**Risk**: User rapidly saves config.json (e.g., during iterative editing), causing many rapid reload cycles.

**Mitigation**: Debounce config file change events by 500ms. Only the last save within the window triggers a reload. This is standard and handles all editors including those that write in stages.

### Risk 4: Sleep During Config Reload

**Risk**: System sleeps in the middle of a config reload operation.

**Mitigation**: Config reload is a fast synchronous file read + JSON decode — it completes in milliseconds. The window for interruption is negligible. No special handling needed.

### Risk 5: ConversionPool State After Wake

**Risk**: If `ConversionPool` actor persists across sleep/wake, its `inFlight` count may be stale (tasks were cancelled but `release()` was never called), preventing new conversions from acquiring slots.

**Mitigation**: `startMonitoring()` in `AppCoordinator` creates a fresh `ConversionPool` instance as part of the full pipeline rebuild. However, currently the conversion pool is created in `start()` (one-time setup) and reused. Two options:
1. Move `ConversionPool` creation into `startMonitoring()` so it's fresh on each wake
2. Add a `reset()` method to `ConversionPool` that zeroes `inFlight` and resumes all waiters

Option 1 is simpler and matches the pattern of creating a fresh `FileWatcher` on each monitoring start.

### Risk 6: AsyncStream Continuation Lifecycle

**Risk**: `FileWatcher.events` uses `AsyncStream` with a continuation set in `init()`. After `stop()`, the continuation's `onTermination` fires. If the stream is still being iterated in a cancelled `eventLoopTask`, there could be a brief period where events are yielded to a cancelled consumer.

**Mitigation**: The `for await` loop in the event loop task naturally exits when the task is cancelled (cooperative cancellation). Creating a new `FileWatcher` per monitoring session (which `startMonitoring()` already does) avoids lifetime issues. The old stream simply finishes.

### Risk 7: Re-Processing Files After Wake

**Risk**: Files that were already successfully processed before sleep get re-detected during the wake re-scan and processed again (e.g., moved twice, converted twice).

**Mitigation**: Successfully processed files are **moved out** of ~/Downloads (to ~/Music, ~/Documents/Papers, etc.) or deleted (duplicates). The re-scan of ~/Downloads only finds files that are still there — i.e., files that arrived during sleep or files whose processing was interrupted. This is self-correcting by design.

### Risk 8: Notification Center Delegate Retention

**Risk**: `UNUserNotificationCenterDelegate` must be retained for the lifetime of the app. If `NotificationManager` is set as the delegate and it's a singleton, this is fine. But if the delegate reference is weak and the object is deallocated, banners stop showing.

**Mitigation**: `NotificationManager.shared` is a static singleton — it lives for the entire app lifetime. Set the delegate in `init()` and it remains valid forever.

---

## RESEARCH COMPLETE
