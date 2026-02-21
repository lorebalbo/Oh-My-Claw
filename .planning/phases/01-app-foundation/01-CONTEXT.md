# Phase 1: App Foundation & File Watching - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish the menu bar app shell (no Dock presence), real-time file monitoring of ~/Downloads via FSEvents, configuration infrastructure (JSON config at ~/Library/Application Support/OhMyClaw/), and structured logging. This is the foundation everything else builds on. No audio processing, no PDF classification, no advanced UI controls — those are later phases.

</domain>

<decisions>
## Implementation Decisions

### Menu Bar UX
- SF Symbol for the menu bar icon (system-native, will match macOS appearance)
- Minimal dropdown in Phase 1: toggle switch for monitoring on/off + Quit — nothing else
- Toggle style: a toggle/switch-style control in the menu (not a text label that changes)
- Monitoring auto-starts on app launch — no user action required to begin watching

### Config Defaults & Structure
- Config location: ~/Library/Application Support/OhMyClaw/config.json (standard macOS path)
- First-launch config: minimal keys only — hardcoded defaults fill in the rest
- Config structure: nested by feature area (e.g., `{ "audio": { ... }, "watcher": { ... } }`)
- Invalid config handling: fallback to defaults for bad values AND notify the user about the invalid config (both behaviors)

### File Watcher Behavior
- Debounce: 3-5 seconds after file activity stops before processing
- File size stability check: yes — verify file size hasn't changed before handing off (on top of debounce)
- Ignore list: extended — .crdownload, .part, .tmp, .download, .partial, .downloading, plus hidden files (dotfiles)
- Existing files on launch: scan and process any matching files already in ~/Downloads when app starts
- Existing file processing: process all matching files in parallel (not sequentially)
- Watch directory: ~/Downloads only, hardcoded (not configurable)
- Subdirectories: top-level ~/Downloads only — no recursive scanning
- Disappeared files: if a file is removed/moved before processing completes, skip it and notify the user via macOS notification

### Logging Detail & Format
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

</decisions>

<specifics>
## Specific Ideas

- The app should feel invisible — no Dock icon, just a menu bar presence
- Config validation should be helpful: tell the user what's wrong, don't just silently fix it
- The watcher should be robust against incomplete downloads — both debounce AND file size stability checks provide double safety

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-app-foundation*
*Context gathered: 2026-02-21*
