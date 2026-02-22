---
phase: 04-pdf-classification
plan: "02"
subsystem: pdf
tags: [openai-api, llm-classification, http-client]

requires:
  - phase: 04-pdf-classification
    provides: "PDFFileIdentifier, PDFTextExtractor, PDFMetadata from plan 01"
provides:
  - "OpenAIClient for HTTP classification via OpenAI API"
  - "PDFTask implementing full PDF classification pipeline"
  - "Menu bar guidance for missing OpenAI API key"
affects: []

tech-stack:
  added: [URLSession-HTTP-client, OpenAI-API]
  patterns: [retry-with-exponential-backoff, conservative-classification, minimum-page-filter]

key-files:
  created:
    - OhMyClaw/PDF/OpenAIClient.swift
    - OhMyClaw/PDF/PDFTask.swift
  modified:
    - OhMyClaw/Config/AppConfig.swift
    - OhMyClaw/Resources/default-config.json
    - OhMyClaw/App/AppCoordinator.swift
    - OhMyClaw/App/AppState.swift
    - OhMyClaw/UI/MenuBarView.swift

key-decisions:
  - "Conservative classification parsing - only explicit JSON true triggers paper move; ambiguous responses default to false"
  - "OpenAI API key must be configured by user in config.json - no default key"
  - "Default model is gpt-4o - configurable via pdf.openaiModel in config.json"
  - "60s request timeout for cloud API (vs 30s for local)"
  - "Single-page PDFs short-circuited before calling the LLM"
  - "Duplicate papers deleted from Downloads instead of left in place"
  - "Move semantics (not copy) for paper routing to avoid duplicate disk usage"

patterns-established:
  - "HTTP client with Bearer token auth and retry with exponential backoff (2s/4s/8s)"
  - "API key validation at launch with menu bar guidance"
  - "Minimum page count filter before LLM classification"

requirements-completed: [PDF-02, PDF-03, PDF-04]

duration: 6min
completed: 2026-02-22
---

# Phase 04 Plan 02: PDF Pipeline & OpenAI Integration Summary

**Wired end-to-end PDF classification pipeline: OpenAI HTTP client with Bearer auth and retry logic, PDFTask file processing with minimum page count filter, and menu bar guidance for missing API key.**

## Performance
- Tasks: 2/2 completed
- Duration: ~6 minutes
- Build: Zero errors on both tasks
- Tests: All existing tests pass unaffected

## Accomplishments
1. Created OpenAIClient with classification (POST to OpenAI /v1/chat/completions, Bearer auth, 60s timeout), and retry wrapper (3 retries with 2s/4s/8s exponential backoff)
2. Created PDFTask conforming to FileTask: extract text -> page count check -> classify with retry -> move papers to ~/Documents/Papers or skip
3. Replaced lmStudioPort and modelName with openaiApiKey and openaiModel in PDFConfig
4. Updated default-config.json with openaiApiKey ("") and openaiModel ("gpt-4o")
5. Wired PDF pipeline in AppCoordinator.start(): creates OpenAIClient, validates API key, registers PDFTask
6. Added openaiApiKeyConfigured flag to AppState for UI binding
7. Added OpenAI API key guidance section to MenuBarView (orange warning)
8. System prompt includes explicit negative examples and structural cues
9. Single-page PDFs are short-circuited before calling the LLM
10. Duplicate papers are deleted from Downloads instead of being left in place

## Files Created/Modified
- **Created:** OhMyClaw/PDF/OpenAIClient.swift - HTTP client with Bearer auth, classification, retry, and conservative parsing
- **Created:** OhMyClaw/PDF/PDFTask.swift - FileTask conformer wiring extract -> classify -> move pipeline with minimum page filter
- **Modified:** OhMyClaw/Config/AppConfig.swift - Replaced lmStudioPort/modelName with openaiApiKey/openaiModel
- **Modified:** OhMyClaw/Resources/default-config.json - Updated pdf section with openaiApiKey and openaiModel
- **Modified:** OhMyClaw/App/AppCoordinator.swift - PDF pipeline wiring with API key validation
- **Modified:** OhMyClaw/App/AppState.swift - Added openaiApiKeyConfigured property
- **Modified:** OhMyClaw/UI/MenuBarView.swift - Added OpenAI API key guidance warning section

## Decisions Made
1. **Conservative parsing:** Only explicit {"is_paper": true} JSON or string match triggers paper classification. All ambiguous responses default to false.
2. **No health polling needed:** OpenAI is a cloud service - just validate the API key is configured at startup.
3. **60s timeout:** Cloud API calls can be slower than local inference. 60s is appropriate.
4. **Duplicate deletion:** Duplicate papers are deleted from Downloads (not skipped) since the paper is already archived in Papers.
5. **Minimum page filter:** Single-page documents (receipts, flyers) are automatically skipped without LLM cost.

## Deviations from Plan
Switched from local LM Studio to OpenAI API (GPT-4o) for classification. This removes the need for LM Studio health polling and replaces it with API key validation.

## Issues Encountered
None.

## Next Phase Readiness
Phase 04 complete. PDF classification pipeline fully wired end-to-end with OpenAI API. Ready for Phase 05.

## Self-Check: PASSED
