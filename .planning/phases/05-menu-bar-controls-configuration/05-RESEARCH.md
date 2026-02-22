# Phase 5: Menu Bar Controls & Configuration - Research

**Researched:** 2026-02-22
**Domain:** SwiftUI MenuBarExtra Dynamic Icons, SF Symbol Animation, SMAppService, In-Menu Settings Controls
**Confidence:** HIGH

## Summary

Phase 5 transforms the current minimal dropdown (monitoring toggle + Quit) into a full control surface with three sections (Monitoring, Settings, App), dynamic menu bar icon state, processing animation, pause/resume, Launch at Login, and live config editing. The deployment target is macOS 14+ (`@Observable`), which unlocks the full SwiftUI MenuBarExtra `.window` style feature set.

The key technical challenges are: (1) `MenuBarExtra(systemImage:)` is static — dynamic icons require the `label:` view builder variant, (2) SF Symbol animation in the menu bar requires a `Timer`-driven frame cycle updating the symbol name on `AppState`, (3) SMAppService is a one-liner for Launch at Login but has a status enum that must be checked on launch (not cached), and (4) SwiftUI form controls (Picker, TextField) work inside `.window` style but need careful sizing and auto-save wiring through `ConfigStore`.

**Primary recommendation:** Add an `AppState` enum for icon state (`idle`, `processing(count)`, `paused`, `error(message)`) that drives both the icon image and the status text. Wire all state changes through `AppCoordinator`, which already owns `AppState` and `ConfigStore`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Icon states & animation
- Use **SF Symbols** — consistent with macOS visual language
- **Same icon, different fills** for state differentiation (e.g. outline for idle, filled for processing)
- **Frame-by-frame animation** while files are actively processing (cycle through 2-3 icon variants)
- **Full icon change** on error state — immediately noticeable, not subtle
- **Dimmed/muted icon** when paused, paired with "Paused" status text

### Menu layout & density
- **Sectioned with dividers** — three sections: Monitoring, Settings, App
- **Medium width** (~300px) to accommodate settings and labels
- **Standard macOS menu** feel (like 1Password or Bartender — native, not custom styled)
- **One-line dynamic status text** at top: "Idle", "Processing 3 files", "Error: conversion failed"
- **ffmpeg warning**: both a macOS notification on launch AND persistent inline note in dropdown
- **Quit button** at bottom of dropdown, always visible

### Settings editing UX
- **Duration threshold**: preset picker (segmented or dropdown) — not a freeform slider or text field
- **Quality cutoff**: dropdown picker listing formats from highest to lowest quality
- **LM Studio port**: text field pre-filled with default 1234, editable for custom setups
- **Auto-save on change** — each setting writes to config immediately, no explicit Save button

### Pause/resume & Launch at Login
- **Pause/resume replaces** the existing monitoring on/off toggle — single control, not two
- Pause stops new file detection; in-flight tasks (conversions, moves) complete
- **Launch at Login** toggle lives in the App section near Quit
- Use **SMAppService** (macOS 13+) for Launch at Login implementation

### Claude's Discretion
- Specific SF Symbol choice for the icon
- Exact frame-by-frame animation timing and variant count
- Precise duration preset values for the picker
- Spacing, typography, and label wording within the dropdown
- How to handle settings validation (e.g. invalid port numbers)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| APP-02 | User can pause monitoring from the menu bar (in-flight tasks continue) | Pause/resume on `AppCoordinator`; stop FileWatcher but let existing `Task`s finish |
| APP-03 | User can toggle Launch at Login from the menu bar | `SMAppService.mainApp.register()` / `.unregister()`, status check on launch |
| APP-04 | Menu bar icon visually indicates app state (idle/processing/error) | `MenuBarExtra(label:)` view builder with `Image(systemName:)` driven by `AppState` enum |
| APP-05 | Menu bar icon animates while files are being processed | `Timer.publish` cycling through 2-3 SF Symbol variants on `AppState.iconName` |
| CFG-02 | User can edit duration threshold from menu bar | SwiftUI `Picker` with preset values (30s, 60s, 90s, 120s), auto-save via `ConfigStore.save()` |
| CFG-03 | User can edit format ranking cutoff from menu bar | SwiftUI `Picker` listing `QualityTier.allCases` reversed, auto-save on change |
| CFG-04 | User can edit LM Studio port from menu bar | SwiftUI `TextField` with `.onSubmit` + validation (1–65535), auto-save on change |
</phase_requirements>

## Standard Stack

### Core
| Library/Framework | Version | Purpose | Why Standard |
|---|---|---|---|
| SwiftUI | macOS 14+ | Full menu bar UI with form controls | `MenuBarExtra` `.window` style supports arbitrary SwiftUI views |
| Observation | macOS 14+ | Reactive state propagation | `@Observable` on `AppState` already in use; drives icon + status updates |
| ServiceManagement | macOS 13+ | Launch at Login | `SMAppService.mainApp` — single API call, no helper app needed |
| Combine (Timer only) | macOS 10.15+ | Animation frame cycling | `Timer.publish` for periodic icon updates during processing |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Timer.publish` for icon animation | `Task.sleep` loop | Timer integrates cleanly with SwiftUI state; Task.sleep works but needs manual cancellation tracking |
| `SMAppService` | LSSharedFileListInsertItemURL (legacy) | Legacy API deprecated since macOS 13; SMAppService is the replacement |
| SwiftUI `Picker` for settings | `NSPopUpButton` via NSViewRepresentable | Unnecessary complexity; native SwiftUI Picker works in `.window` style |
| `@Observable` property for icon name | `NSStatusItem.button.image` direct manipulation | Would bypass SwiftUI; MenuBarExtra label view builder handles this natively |

## Architecture Patterns

### Pattern 1: App State Enum for Icon + Status
**What:** Replace the boolean `isMonitoring` with an enum that captures all visual states. This single enum drives both the menu bar icon and the status text line.
**When to use:** Menu bar icon rendering and status text display.
**Confidence:** HIGH

```swift
/// Represents the visual state of the app for both icon and status text.
enum MonitoringState: Equatable {
    case idle
    case processing(count: Int)
    case paused
    case error(message: String)

    var statusText: String {
        switch self {
        case .idle: return "Idle"
        case .processing(let count): return "Processing \(count) file\(count == 1 ? "" : "s")"
        case .paused: return "Paused"
        case .error(let message): return "Error: \(message)"
        }
    }
}
```

The existing `AppState` gains:
```swift
@Observable
final class AppState {
    var monitoringState: MonitoringState = .idle
    var ffmpegAvailable: Bool = true
    var lmStudioAvailable: Bool = true
    var processingCount: Int = 0            // incremented/decremented by coordinator
    var lastError: String? = nil            // set on task failure, cleared on next success
}
```

`monitoringState` is a computed-style value updated by `AppCoordinator` whenever `processingCount`, pause state, or error state changes. The coordinator is the authoritative source.

### Pattern 2: Dynamic Menu Bar Icon via Label View Builder
**What:** Use `MenuBarExtra`'s `label:` view builder instead of the static `systemImage:` parameter. The label view reads from `@Observable` state.
**When to use:** OhMyClawApp.swift — the app entry point.
**Confidence:** HIGH

```swift
@main
struct OhMyClawApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(coordinator)
        } label: {
            Image(systemName: coordinator.appState.menuBarIcon)
                .symbolRenderingMode(coordinator.appState.iconRenderingMode)
        }
        .menuBarExtraStyle(.window)
    }
}
```

The `menuBarIcon` and `iconRenderingMode` are computed properties on `AppState`:
```swift
extension AppState {
    /// The SF Symbol name for the current state.
    var menuBarIcon: String {
        switch monitoringState {
        case .idle:
            return "arrow.down.doc"
        case .processing:
            return animatedIconName       // cycles through variants
        case .paused:
            return "arrow.down.doc"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var iconRenderingMode: SymbolRenderingMode {
        switch monitoringState {
        case .paused: return .hierarchical   // dimmed effect
        default: return .monochrome
        }
    }
}
```

**Critical:** The static `MenuBarExtra("title", systemImage: "icon")` initializer does NOT update the icon when state changes. You MUST use the `label:` view builder variant for dynamic icons.

### Pattern 3: Timer-Driven Frame Animation
**What:** While processing, cycle the menu bar icon through 2-3 SF Symbol variants at a fixed interval to convey activity.
**When to use:** When `monitoringState` is `.processing`.
**Confidence:** HIGH

```swift
/// Manages menu bar icon animation frames.
@MainActor
@Observable
final class IconAnimator {
    private(set) var currentFrame: Int = 0
    private var timer: Timer?

    /// SF Symbol names to cycle through during processing.
    private let frames = [
        "arrow.down.doc",
        "arrow.down.doc.fill",
        "arrow.up.doc"
    ]

    var currentIconName: String {
        frames[currentFrame % frames.count]
    }

    func startAnimating() {
        guard timer == nil else { return }
        currentFrame = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentFrame += 1
            }
        }
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        currentFrame = 0
    }
}
```

**Timing recommendation:** 0.5s per frame (2 FPS) — fast enough to convey activity, slow enough not to be distracting in the menu bar. Three frames provides a smooth cycle without excessive symbol lookup.

**Integration:** `AppCoordinator` starts/stops the `IconAnimator` when `processingCount` transitions between 0 and >0. `AppState.animatedIconName` reads from `IconAnimator.currentIconName`.

### Pattern 4: SMAppService for Launch at Login
**What:** Use `ServiceManagement.SMAppService.mainApp` to register/unregister the app as a Login Item.
**When to use:** Launch at Login toggle in the App section.
**Confidence:** HIGH

```swift
import ServiceManagement

extension AppState {
    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLogger.shared.error("Launch at Login failed",
                context: ["action": enabled ? "register" : "unregister",
                          "error": error.localizedDescription])
        }
    }
}
```

**Key details:**
- `SMAppService.mainApp` refers to the currently running app. No helper app or bundle ID needed.
- `.register()` and `.unregister()` are synchronous and can throw.
- `.status` returns `.enabled`, `.notRegistered`, `.notFound`, or `.requiresApproval`.
- Always read `.status` live — do NOT cache it. The user can change Login Items in System Settings independently.
- Works for non-sandboxed apps distributed outside the App Store.
- Available macOS 13+; our target is macOS 14+, so no compatibility concern.

### Pattern 5: Auto-Save Settings via ConfigStore
**What:** Each settings control writes to `ConfigStore` immediately on value change. No Save button.
**When to use:** Duration picker, quality cutoff picker, LM Studio port field.
**Confidence:** HIGH

```swift
// In MenuBarView, settings section:
Picker("Min Duration", selection: Binding(
    get: { coordinator.configStore.config.audio.minDurationSeconds },
    set: { newValue in
        var config = coordinator.configStore.config
        config.audio.minDurationSeconds = newValue
        coordinator.configStore.save(config)
    }
)) {
    Text("30s").tag(30)
    Text("60s").tag(60)
    Text("90s").tag(90)
    Text("120s").tag(120)
}
```

The existing `ConfigStore.save(_:)` already writes to disk atomically and updates the in-memory `config`. No new infrastructure needed — just expose `configStore` from `AppCoordinator` to the view.

### Pattern 6: Sectioned Menu Layout
**What:** Three visual sections separated by `Divider()` within the `.window` style MenuBarExtra.
**When to use:** MenuBarView layout.
**Confidence:** HIGH

```
┌──────────────────────────────┐
│ ● Idle                       │  ← Status text (dynamic)
├──────────────────────────────┤
│ MONITORING                   │
│ [Pause Monitoring]           │  ← Button (toggles to "Resume")
│                              │
│ ⚠ ffmpeg not found           │  ← Inline warning (conditional)
│   brew install ffmpeg        │
├──────────────────────────────┤
│ SETTINGS                     │
│ Min Duration    [60s ▾]      │  ← Preset picker
│ Quality Cutoff  [MP3 320 ▾]  │  ← Dropdown picker
│ LM Studio Port  [1234   ]   │  ← Text field
├──────────────────────────────┤
│ APP                          │
│ ☐ Launch at Login            │  ← Toggle
│ [Quit Oh My Claw]            │  ← Button
└──────────────────────────────┘
  ~300px wide
```

### Pattern 7: Pause/Resume Semantics
**What:** Pause stops the FileWatcher (no new file detection) but does NOT cancel in-flight tasks. Resume restarts the FileWatcher and rescans ~/Downloads.
**When to use:** Pause/Resume button action.
**Confidence:** HIGH

```swift
// In AppCoordinator:
func pauseMonitoring() {
    appState.monitoringState = .paused
    fileWatcher?.stop()           // stop FSEvents stream
    fileWatcher = nil
    // Do NOT cancel eventLoopTask — let in-flight tasks finish naturally
    // The for-await loop will end when the watcher's AsyncStream terminates
    AppLogger.shared.info("Monitoring paused by user")
}

func resumeMonitoring() async {
    appState.monitoringState = .idle
    await startMonitoring()       // restarts FileWatcher + event loop + rescan
    AppLogger.shared.info("Monitoring resumed by user")
}
```

**Critical distinction from current `stopMonitoring()`:** The current implementation cancels `eventLoopTask`, which would cancel in-flight processing. The pause variant must stop only the watcher, allowing the existing event loop iteration to complete any file it's already processing. Once the watcher's `AsyncStream` finishes (because the watcher stopped), the `for await` loop exits naturally.

### Anti-Patterns to Avoid
- **Static `systemImage:` for dynamic icons:** The `MenuBarExtra("title", systemImage: "icon")` initializer bakes in the icon at init time. Use the `label:` view builder.
- **Caching `SMAppService.mainApp.status`:** The user can change Login Items externally. Always read `.status` live when rendering the toggle.
- **Canceling event loop on pause:** This kills in-flight task processing. Only stop the watcher; let the loop drain.
- **`Task.sleep` for animation:** Harder to cancel cleanly than `Timer`. Use `Timer.scheduledTimer` on main run loop.
- **Using `.menu` style for settings controls:** The `.menu` style only supports `Button`, `Toggle`, `Divider`, `Picker` (limited). The `.window` style is required for `TextField`, custom layouts, and section headers. Already in use.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Launch at Login | LaunchAgent plist or helper app | `SMAppService.mainApp` | One-line API, no helper binary, macOS 13+ standard |
| Menu bar icon management | `NSStatusItem.button.image` direct manipulation | `MenuBarExtra(label:)` view builder | Stays in SwiftUI, reacts to `@Observable` state |
| Settings persistence | Manual JSON write on each keystroke | `ConfigStore.save(_:)` in Picker/TextField `.onChange` | Already implemented, atomic write, validation included |
| Icon animation | CADisplayLink / custom run loop | `Timer.scheduledTimer` at 0.5s interval | Sufficient for 2-3 frame icon cycling, minimal CPU |
| Port number validation | Regex or custom parser | `Int(text)` + range check 1…65535 | Simple, reliable, matches existing `ConfigStore.validate()` |

## Common Pitfalls

### Pitfall 1: MenuBarExtra Icon Not Updating on State Change
**What goes wrong:** The menu bar icon stays static even though `AppState` changes.
**Why it happens:** Using `MenuBarExtra("title", systemImage: "fixed.icon")` — the `systemImage` parameter is evaluated once at init.
**How to avoid:** Use the `label:` view builder variant. The `Image(systemName:)` inside the label reads from `@Observable` state and re-renders on change.
**Warning signs:** Icon stuck on initial value, no visual feedback during processing.
**Confidence:** HIGH — this is a well-documented SwiftUI behavior.

### Pitfall 2: SMAppService Status Stale After External Change
**What goes wrong:** The Launch at Login toggle shows the wrong state after the user changes Login Items in System Settings → General → Login Items.
**Why it happens:** Caching the status value at app launch and never re-reading it.
**How to avoid:** Read `SMAppService.mainApp.status` in the Toggle's getter, not from a stored property. The call is lightweight (no disk I/O).
**Warning signs:** Toggle state disagrees with System Settings.
**Confidence:** HIGH

### Pitfall 3: Pausing Cancels In-Flight Tasks
**What goes wrong:** User pauses monitoring and an ongoing ffmpeg conversion is killed mid-process, leaving a corrupted partial file.
**Why it happens:** Canceling the `eventLoopTask` propagates cancellation to the `await task.process(file:)` call currently executing.
**How to avoid:** On pause, stop only the `FileWatcher` (which terminates the `AsyncStream`). The `for await` loop exits after the current iteration completes. Do NOT call `eventLoopTask?.cancel()`.
**Warning signs:** Partial files in ~/Music, ffmpeg exit code 255, "task cancelled" errors in logs.
**Confidence:** HIGH — directly relevant to existing code structure.

### Pitfall 4: Timer Animation Runs When There's Nothing to Animate
**What goes wrong:** The icon animation timer keeps firing after all files are processed, wasting CPU and battery.
**Why it happens:** Starting the timer on first processing event but not stopping it when `processingCount` drops to 0.
**How to avoid:** Use a `didSet` observer or explicit check in `AppCoordinator`: when `processingCount` transitions to 0, call `iconAnimator.stopAnimating()`. When it transitions from 0 to >0, call `startAnimating()`.
**Warning signs:** Constant 2/sec timer fires visible in Instruments, menu bar icon cycling when app is idle.
**Confidence:** HIGH

### Pitfall 5: TextField In MenuBarExtra Panel Loses Focus on Click Outside
**What goes wrong:** User is editing the LM Studio port, clicks elsewhere in the panel, and the TextField loses focus without saving.
**Why it happens:** The `.window` style MenuBarExtra is an `NSPanel` — standard focus behavior.
**How to avoid:** Use `.onSubmit` for explicit Enter-key save AND `.onChange(of:)` for auto-save on every valid change. Both paths go through the same validation + `ConfigStore.save()`. Also consider `.onExitCommand` as a cancel path.
**Warning signs:** Port changes lost, user confusion about when changes take effect.
**Confidence:** MEDIUM — depends on exact focus behavior of the panel.

### Pitfall 6: Processing Count Tracking Across Concurrent Tasks
**What goes wrong:** `processingCount` goes negative or doesn't return to 0, leaving the icon stuck in animation mode.
**Why it happens:** Incrementing/decrementing without proper error handling — if `process(file:)` throws before the decrement, the count stays inflated.
**How to avoid:** Use `defer { processingCount -= 1 }` immediately after the increment, or wrap in a helper that guarantees balanced counting:
```swift
func trackProcessing<T>(_ work: () async throws -> T) async rethrows -> T {
    appState.processingCount += 1
    defer { appState.processingCount -= 1 }
    return try await work()
}
```
**Warning signs:** Icon animation never stops, status text shows "Processing 0 files" or negative count.
**Confidence:** HIGH

## Code Examples

### Complete MenuBarExtra with Dynamic Icon
```swift
@main
struct OhMyClawApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(coordinator)
        } label: {
            switch coordinator.appState.monitoringState {
            case .paused:
                Image(systemName: "arrow.down.doc")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
            default:
                Image(systemName: coordinator.appState.menuBarIcon)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
```

### Full MenuBarView Layout
```swift
struct MenuBarView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // — Status —
            statusSection

            Divider()

            // — Monitoring —
            monitoringSection

            Divider()

            // — Settings —
            settingsSection

            Divider()

            // — App —
            appSection
        }
        .padding(16)
        .frame(width: 300)
        .task {
            await coordinator.start()
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(coordinator.appState.monitoringState.statusText)
                .font(.headline)
        }
    }

    private var statusColor: Color {
        switch coordinator.appState.monitoringState {
        case .idle: return .green
        case .processing: return .blue
        case .paused: return .gray
        case .error: return .red
        }
    }

    // MARK: - Monitoring

    @ViewBuilder
    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monitoring")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Button(pauseButtonLabel) {
                Task {
                    if case .paused = coordinator.appState.monitoringState {
                        await coordinator.resumeMonitoring()
                    } else {
                        coordinator.pauseMonitoring()
                    }
                }
            }

            // Inline ffmpeg warning
            if !coordinator.appState.ffmpegAvailable {
                Label("ffmpeg not found", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Install via: brew install ffmpeg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pauseButtonLabel: String {
        if case .paused = coordinator.appState.monitoringState {
            return "Resume Monitoring"
        }
        return "Pause Monitoring"
    }

    // MARK: - Settings

    @ViewBuilder
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Duration picker — preset values
            LabeledContent("Min Duration") {
                Picker("", selection: durationBinding) {
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                    Text("90s").tag(90)
                    Text("120s").tag(120)
                }
                .labelsHidden()
                .frame(width: 80)
            }

            // Quality cutoff picker — all tiers, highest to lowest
            LabeledContent("Quality Cutoff") {
                Picker("", selection: qualityCutoffBinding) {
                    ForEach(QualityTier.allCases.reversed(), id: \.self) { tier in
                        Text(tier.displayName).tag(tier.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            // LM Studio port — text field
            LabeledContent("LM Studio Port") {
                TextField("1234", text: portBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit { validateAndSavePort() }
            }
        }
    }

    // MARK: - App

    @ViewBuilder
    private var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle("Launch at Login", isOn: launchAtLoginBinding)
                .toggleStyle(.switch)

            Button("Quit Oh My Claw") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

### SMAppService Toggle Binding
```swift
private var launchAtLoginBinding: Binding<Bool> {
    Binding(
        get: { SMAppService.mainApp.status == .enabled },
        set: { newValue in
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                AppLogger.shared.error("Launch at Login toggle failed",
                    context: ["error": error.localizedDescription])
            }
        }
    )
}
```

### Processing Count Tracking in AppCoordinator
```swift
// Inside the event loop, wrap task processing:
for task in self.tasks where task.isEnabled && task.canHandle(file: fileURL) {
    self.appState.processingCount += 1
    defer { self.appState.processingCount -= 1 }

    do {
        let result = try await task.process(file: fileURL)
        // ... handle result
        self.appState.lastError = nil  // clear error on success
    } catch {
        self.appState.lastError = error.localizedDescription
        // ... handle error
    }
    break
}

// After the loop, update monitoring state:
private func updateMonitoringState() {
    if case .paused = appState.monitoringState { return }  // don't override paused
    if let error = appState.lastError {
        appState.monitoringState = .error(message: error)
    } else if appState.processingCount > 0 {
        appState.monitoringState = .processing(count: appState.processingCount)
    } else {
        appState.monitoringState = .idle
    }
}
```

### Port Validation Pattern
```swift
@State private var portText: String = ""

private var portBinding: Binding<String> {
    Binding(
        get: { String(coordinator.configStore?.config.pdf.lmStudioPort ?? 1234) },
        set: { portText = $0 }
    )
}

private func validateAndSavePort() {
    guard let port = Int(portText), (1...65535).contains(port) else {
        // Reset to current valid value
        portText = String(coordinator.configStore?.config.pdf.lmStudioPort ?? 1234)
        return
    }
    var config = coordinator.configStore!.config
    config.pdf.lmStudioPort = port
    coordinator.configStore!.save(config)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| NSStatusItem + NSMenu (AppKit) | SwiftUI `MenuBarExtra` with `.window` style | macOS 13 (2022) | Full SwiftUI views in menu bar dropdown |
| `MenuBarExtra(systemImage:)` static | `MenuBarExtra(label:)` view builder | macOS 13 (2022) | Dynamic icon updates from `@Observable` state |
| SMLoginItemSetEnabled + helper bundle | `SMAppService.mainApp.register()` | macOS 13 (2022) | One-liner Launch at Login, no helper binary |
| NSTimer / DispatchSourceTimer | `Timer.scheduledTimer` / `Timer.publish` | Swift 5+ | Timer-driven animation with SwiftUI integration |
| `@StateObject` + `ObservableObject` | `@Observable` + `@State` | macOS 14 (2023) | Simpler observation, no manual `objectWillChange` |

## Open Questions

1. **MenuBarExtra label view builder reactivity on macOS 14**
   - What we know: The `label:` view builder with `@Observable` state changes should trigger re-renders of the menu bar icon.
   - What's unclear: Some reports suggest early macOS 14 betas had issues with label view builder updates. This appears resolved in release builds.
   - Recommendation: Implement with the `label:` view builder. If updates don't propagate, fallback to setting `NSApp.setActivationPolicy` trick to force redraw. LOW risk.
   - **Confidence:** HIGH that it works on macOS 14.0+.

2. **Icon rendering in dark/light menu bar**
   - What we know: SF Symbols in menu bar automatically adapt to the bar's appearance (dark/light).
   - What's unclear: Whether `.hierarchical` rendering mode for the paused state looks distinct enough in both appearances.
   - Recommendation: Test both appearances. If `.hierarchical` is too subtle, use `.opacity(0.5)` modifier instead.
   - **Confidence:** MEDIUM — visual-only concern, easy to adjust.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) (macOS 13+)
- Apple Developer Documentation — [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) (macOS 13+)
- Apple Developer Documentation — [Observable](https://developer.apple.com/documentation/observation/observable()) (macOS 14+)
- Apple Developer Documentation — [SF Symbols](https://developer.apple.com/sf-symbols/) (symbol names, rendering modes)
- Existing codebase — `AppState.swift`, `AppCoordinator.swift`, `ConfigStore.swift`, `MenuBarView.swift`, `QualityEvaluator.swift`

### Secondary (MEDIUM confidence)
- SwiftUI MenuBarExtra `.window` style behavior — community-validated patterns for form controls in menu bar panels
- Timer-based animation patterns — standard Cocoa/SwiftUI animation technique

## Metadata

**Confidence breakdown:**
- Dynamic icon via label view builder: HIGH — documented API, community-verified
- SMAppService for Launch at Login: HIGH — straightforward API, available since macOS 13
- Timer-driven icon animation: HIGH — standard pattern, no edge cases
- SwiftUI form controls in `.window` style: HIGH — already using `.window` style in the app
- Pause semantics (stop watcher, keep tasks): HIGH — clear from existing code structure
- Auto-save settings: HIGH — `ConfigStore.save()` already exists and works
- TextField focus behavior in NSPanel: MEDIUM — may need runtime testing

**Research date:** 2026-02-22
**Valid until:** 2026-08-22 (stable APIs, no expected breaking changes)
