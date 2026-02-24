---
status: complete
phase: 06-resilience-polish
source: [06-01-SUMMARY.md, 06-02-SUMMARY.md]
started: 2026-02-22T20:53:00Z
updated: 2026-02-24T21:18:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Error Notification Batching
expected: When multiple file errors occur in rapid succession, they are batched into a single notification (3-second window) rather than spamming one notification per error.
result: pass

### 2. Error Cooldown Prevents Spam
expected: After an error notification fires for a category, the same category does not produce another notification for 5 minutes — repeated errors within the cooldown window are silently absorbed.
result: issue
reported: "I changed the api key to one that doesn't exist to trigger an error but no notification showed. Logs show classification failures with badResponse(statusCode: 401) but no notification is sent."
severity: major

### 3. Foreground Banner Display
expected: When the menu bar popover is open and an error occurs, the notification still appears as a system banner (UNUserNotificationCenter delegate delivers it in foreground).
result: skipped
reason: Blocked by Test 2 — error notifications not firing for PDF classification failures

### 4. Config Hot-Reload
expected: Edit the config JSON file (~/.config/ohmyclaw/config.json or the app's config location) in an external editor (e.g. TextEdit, VS Code), save, and changes take effect immediately — no app restart needed. A "Config reloaded" notification appears.
result: pass

### 5. Invalid Config Keeps Last Good
expected: Save an invalid JSON config (e.g. remove a closing brace). The app keeps the last valid configuration active, shows an error notification about the invalid config, and continues operating normally.
result: pass
notes: User requests notification should explicitly say config.json is corrupted but app continues with last correct version. Also wants: (1) repeated saves of corrupted config should keep the last known-good version in memory, (2) last known-good config should persist across app restarts.

### 6. Sleep/Wake Recovery
expected: After macOS wakes from sleep, file monitoring resumes automatically. Files that arrived in ~/Downloads during sleep are detected and processed on wake.
result: pass

## Summary

total: 6
passed: 4
issues: 1
pending: 0
skipped: 1

## Gaps

- truth: "Error notifications should fire when PDF classification fails due to API errors"
  status: failed
  reason: "User reported: Changed API key to invalid one, classification fails with 401 but no notification shown. PDFTask returns .skipped instead of .error for classification failures, bypassing ErrorCollector."
  severity: major
  test: 2
  root_cause: "PDFTask.process() returns .skipped(reason: 'Classification failed — leaving in Downloads') on line 71 instead of .error(description:). AppCoordinator only routes .error results through ErrorCollector — .skipped results are logged as info and ignored."
  artifacts:
    - path: "OhMyClaw/PDF/PDFTask.swift"
      issue: "Line 71: returns .skipped for API failures instead of .error"
    - path: "OhMyClaw/App/AppCoordinator.swift"
      issue: "Lines 207-210: .skipped case only logs, does not route through ErrorCollector"
  missing:
    - "Change PDFTask to return .error(description:) when classification fails after all retries"
