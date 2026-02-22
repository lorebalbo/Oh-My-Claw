---
status: complete
phase: 04-pdf-classification
source: [04-01-SUMMARY.md, 04-02-SUMMARY.md]
started: 2026-02-22T12:00:00Z
updated: 2026-02-22T12:05:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 0
name: n/a
expected: n/a
awaiting: n/a

[testing complete]

## Tests

### 1. LM Studio Unavailable Guidance
expected: With LM Studio NOT running, launch the app. The menu bar dropdown should show an orange warning: "LM Studio not reachable" with guidance text about ensuring LM Studio is running and that PDF classification is paused.
result: pass

### 2. Scientific Paper Classification & Move
expected: With LM Studio running and a model loaded, drop a scientific paper PDF into ~/Downloads. The app should detect it, extract text, classify it as a paper via LM Studio, and move it to ~/Documents/Papers (auto-created if it doesn't exist). The PDF should no longer be in ~/Downloads.
result: pass

### 3. Non-Paper PDF Left Untouched
expected: With LM Studio running, drop a non-paper PDF (e.g., an invoice, receipt, or product manual) into ~/Downloads. The app should classify it as NOT a paper and leave it in ~/Downloads untouched.
result: issue
reported: "Dropped a GitHub issue PDF (not a scientific paper) and OhMyClaw moved it to Documents/Papers. The LLM classified it as a paper incorrectly. Logs confirm the pipeline ran (extract → classify → move) but the classification result was wrong."
severity: major

### 4. LM Studio Recovery & Auto-Dismiss
expected: With the app running and LM Studio initially stopped (orange warning visible), start LM Studio and load a model. Within ~60 seconds the orange warning should auto-dismiss from the menu bar, and any PDFs that were skipped in ~/Downloads should be rescanned.
result: pass

### 5. Duplicate Paper Handling
expected: Drop a paper PDF into ~/Downloads that has already been moved to ~/Documents/Papers (same filename). The app should skip it without overwriting or renaming — the original in ~/Documents/Papers stays unchanged, and the duplicate remains in ~/Downloads.
result: pass
note: "User prefers duplicates to be deleted from Downloads instead of skipped/left in place"

## Summary

total: 5
passed: 4
issues: 1
pending: 0
skipped: 0

## Gaps

- truth: "Non-paper PDFs (invoice, receipt, GitHub issue) are left in ~/Downloads untouched"
  status: failed
  reason: "User reported: Dropped a GitHub issue PDF (not a scientific paper) and OhMyClaw moved it to Documents/Papers. The LLM classified it as a paper incorrectly."
  severity: major
  test: 3
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
