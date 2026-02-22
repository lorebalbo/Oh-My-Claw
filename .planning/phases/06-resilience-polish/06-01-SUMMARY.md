---
phase: 06-resilience-polish
plan: "01"
subsystem: infrastructure
tags: [error-handling, notifications, batching, cooldown]
requires: []
provides: [error-collector, foreground-banners, error-routing]
affects: [AppCoordinator, NotificationManager]
key-files:
  - OhMyClaw/Infrastructure/ErrorCollector.swift
  - OhMyClaw/Infrastructure/NotificationManager.swift
  - OhMyClaw/App/AppCoordinator.swift
key-decisions:
  - Actor-based ErrorCollector with 3s batch window and per-category cooldown (5min default, 10s for configReload)
  - Stable notification identifiers per category enable replacement-based batching
  - NotificationManager inherits NSObject for UNUserNotificationCenterDelegate conformance
  - Error category mapping kept in AppCoordinator (not on FileTask protocol) to avoid protocol changes
requirements-completed: [INF-02]
duration: ~5 min
completed: 2026-02-22
---

# Plan 06-01 Summary: Error Notification System

Error notification system with actor-based batching (3s window) and per-category cooldown (5min) to prevent notification spam, with foreground banner support and full event loop error routing.

## Performance
- **Duration**: ~5 min
- **Started**: 2026-02-22
- **Completed**: 2026-02-22
- **Tasks**: 3/3
- **Files**: 1 created, 2 modified

## Accomplishments
- Created `ErrorCollector` actor with 7-category enum, 3-second batch window, per-category cooldown (5 minutes default, 10 seconds for config reload), and utility methods for sleep/wake lifecycle
- Added `UNUserNotificationCenterDelegate` conformance to `NotificationManager` for foreground banner display (banners show even when popover is open)
- Wired all three error paths in AppCoordinator's event loop (TaskResult.error, catch block, file-disappeared) through ErrorCollector for batched notifications
- Added `notifyConfigReloaded()` convenience method for Plan 06-02

## Task Commits

| # | Task | Commit | Hash |
|---|------|--------|------|
| 1 | ErrorCollector actor with batching and cooldown | `feat(06-01): add ErrorCollector actor with batching and cooldown` | `efea5c9` |
| 2 | NotificationManager delegate for foreground banners | `feat(06-01): add UNUserNotificationCenterDelegate for foreground banners` | `c1141e7` |
| 3 | Wire ErrorCollector into AppCoordinator event loop | `feat(06-01): wire ErrorCollector into AppCoordinator event loop` | `259654a` |

## Files Created
- `OhMyClaw/Infrastructure/ErrorCollector.swift` — ErrorCategory enum (7 cases), ErrorInfo struct, ErrorCollector actor

## Files Modified
- `OhMyClaw/Infrastructure/NotificationManager.swift` — NSObject inheritance, UNUserNotificationCenterDelegate, foreground banners, notifyConfigReloaded()
- `OhMyClaw/App/AppCoordinator.swift` — errorCollector property, errorCategory(for:) helper, error routing in event loop

## Decisions Made
1. **Actor over class+lock**: ErrorCollector uses Swift actor for thread-safe state — no manual locking needed
2. **Stable notification identifiers**: Each category uses `"error-{category}"` enabling UNUserNotificationCenter replacement semantics
3. **Category mapping in coordinator**: `errorCategory(for:)` maps task.id → ErrorCategory in AppCoordinator rather than adding protocol requirements — keeps the change localized
4. **Cooldown differentiation**: configReload uses 10s cooldown (user-initiated) while all others use 5min (automated)
5. **notifyFileDisappeared preserved**: The method remains on NotificationManager for backward compatibility but event loop now routes through ErrorCollector

## Deviations from Plan
None.

## Issues Encountered
None.

## Next Phase Readiness
Plan 06-02 (config hot-reload and sleep/wake recovery) can proceed:
- ErrorCollector exposes `cancelPendingTimers()`, `flushAll()`, and `resetCooldowns()` for sleep/wake lifecycle
- `notifyConfigReloaded()` is ready on NotificationManager for config reload success notifications
