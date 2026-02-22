# Phase 6: Resilience & Polish - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Production hardening for Oh My Claw — error notifications that surface processing failures to the user via macOS Notification Center, live config hot-reload so changes from any source (menu bar UI or external text editor) take effect immediately, and sleep/wake recovery so file monitoring resumes reliably after macOS sleeps. Requirements: CFG-05, INF-02, INF-04.

</domain>

<decisions>
## Implementation Decisions

### Error notification behavior
- **All errors** trigger notifications — every failed file operation, conversion failure, LM Studio timeout, etc.
- **Batch multiple errors** into a single notification when they occur quickly (e.g., "3 files failed processing")
- **Include sound** on error notifications (default macOS notification sound)
- **Cooldown per error type** — same error type (e.g., repeated LM Studio unavailable) is suppressed for a window to prevent spam

### Config hot-reload semantics
- **In-flight tasks keep old config** — currently running conversions/moves complete with the config they started with; new config applies to the next files only
- **Invalid external edits** — keep old config active, notify the user that the edit was invalid (don't reset to defaults)
- **Detection via FSEvents** — watch the config.json file itself with an FSEvents file watcher (not polling)
- **Notify on every successful reload** — user should know config was picked up, even for valid changes

### Sleep/wake recovery
- **Restart FSEvent stream + full re-scan** of ~/Downloads on wake to catch files that arrived during sleep
- **Cancel and reprocess** interrupted tasks (e.g., mid-conversion ffmpeg killed by sleep) — re-detect and re-convert from scratch rather than attempting partial resume
- **Silent recovery** — no notification to the user that monitoring resumed; just work
- **NSWorkspace notifications** (willSleep/didWake) for detecting sleep/wake events

### Claude's Discretion
- Cooldown window duration (reasonable default, e.g., 5 minutes)
- Batching window duration for grouping rapid errors
- Any internal error categorization taxonomy
- FSEvents latency/flags for config file watcher

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 06-resilience-polish*
*Context gathered: 2026-02-22*
