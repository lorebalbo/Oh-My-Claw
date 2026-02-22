---
status: diagnosed
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

### 1. OpenAI API Key Not Configured
expected: With pdf.openaiApiKey empty or missing in config.json, launch the app. The menu bar dropdown should show an orange warning: "OpenAI API key not set" with guidance text about adding the key to config.json and that PDF classification is disabled.
result: pass

### 2. Scientific Paper Classification & Move
expected: With a valid OpenAI API key configured, drop a scientific paper PDF (multi-page with abstract, references, etc.) into ~/Downloads. The app should detect it, extract text, classify it as a paper via OpenAI API, and move it to ~/Documents/Papers (auto-created if needed). The PDF should no longer be in ~/Downloads.
result: pass

### 3. Non-Paper PDF Left Untouched
expected: With a valid API key, drop a non-paper PDF (e.g., an invoice, receipt, GitHub issue, or product manual) into ~/Downloads. The app should classify it as NOT a paper and leave it in ~/Downloads untouched.
result: pass

### 4. Single-Page PDF Skipped Without LLM Call
expected: Drop a single-page PDF (receipt, flyer, etc.) into ~/Downloads. The app should skip classification entirely without calling the OpenAI API and leave the file in ~/Downloads. Logs should show "Only 1 page(s) - not a paper".
result: pass

### 5. Duplicate Paper Handling
expected: Drop a paper PDF into ~/Downloads that has already been moved to ~/Documents/Papers (same filename). The app should delete the duplicate from ~/Downloads. The original in ~/Documents/Papers stays unchanged.
result: pass

## Summary

total: 5
passed: 5
issues: 0
pending: 0
skipped: 0

## Gaps

None - all tests pass with OpenAI API integration.
