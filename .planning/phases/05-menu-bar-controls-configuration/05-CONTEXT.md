# Phase 5: Menu Bar Controls & Configuration - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Full menu bar UI with dynamic state indicators, icon animation, pause/resume, Launch at Login, and in-app settings editing. Transforms the current minimal dropdown (monitoring toggle + Quit) into a proper control surface. Requirements: APP-02, APP-03, APP-04, APP-05, CFG-02, CFG-03, CFG-04.

</domain>

<decisions>
## Implementation Decisions

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

</decisions>

<specifics>
## Specific Ideas

- Status text should be dynamic and contextual: "Idle", "Processing 3 files", "Error: conversion failed"
- The paused state should feel distinct — dimmed icon plus status text, not just a toggle flip
- Settings should auto-save with no friction — change a value, it takes effect immediately
- Keep the native macOS feel throughout — no custom styling or non-standard UI patterns

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-menu-bar-controls-configuration*
*Context gathered: 2026-02-22*
