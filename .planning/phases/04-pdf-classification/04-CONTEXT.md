# Phase 4: PDF Classification - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Classify PDF files in ~/Downloads as scientific papers using the OpenAI API (e.g., GPT-4o) and route them to ~/Documents/Papers; leave non-papers untouched. This phase builds on Phase 1's file watcher and config infrastructure to add a second file processing pipeline alongside the audio pipeline.

**Requirements:** PDF-01, PDF-02, PDF-03, PDF-04

</domain>

<decisions>
## Implementation Decisions

### Text Extraction Strategy
- **Extraction approach:** Extract the full text content of the PDF using PDFKit and send it to the OpenAI API for classification
- **PDF metadata inclusion:** Include PDF document attributes (title, author, subject) from PDFKit alongside extracted body text when sending to the LLM
- **Text cleanup:** Apply basic cleanup before sending - strip headers, footers, page numbers, and excessive whitespace
- **No token cap:** Send the full extracted text to the LLM - large models like GPT-4o have ample context windows (128k tokens) to handle full documents
- **Scanned/image PDFs:** If no text can be extracted (image-only PDFs), skip classification entirely, leave in Downloads, and log a warning
- **Language:** Classify regardless of language - a scientific paper is a scientific paper whether in English, Italian, German, etc.
- **Minimum page count:** PDFs with fewer than 2 pages are automatically skipped - single-page documents (receipts, flyers, etc.) are not scientific papers

### LLM Classification Behavior
- **Response format:** Binary yes/no classification (is_paper: true/false) - no confidence scores or reasoning
- **Ambiguous results:** Conservative approach - if classification is uncertain or the LLM response can't be parsed, leave the PDF in Downloads (better to miss a paper than misfile a receipt)
- **Paper definition:** Broad - any academic/research document qualifies (peer-reviewed articles, preprints, conference papers, theses, dissertations, technical reports)
- **Prompt design:** Claude's discretion - design an effective system prompt and user prompt for binary scientific paper classification with explicit negative examples and structural cues

### OpenAI API Connectivity
- **API endpoint:** OpenAI chat completions (https://api.openai.com/v1/chat/completions)
- **Model selection:** Configurable model name in config.json via `pdf.openaiModel` - defaults to `gpt-4o`
- **API key:** User provides their OpenAI API key in config.json via `pdf.openaiApiKey`
- **Request timeout:** 60 seconds per classification request (cloud API may be slower than local)
- **Retry strategy:** 3 retries (4 total attempts) with exponential backoff (2s, 4s, 8s) before giving up on a single PDF
- **Failure behavior:** After all retries exhausted, leave PDF in Downloads and log the failure
- **Startup behavior:** Validate that `pdf.openaiApiKey` is set and non-empty at launch; if missing, show a persistent menu bar message guiding the user to add the API key in config.json
- **Authentication:** Bearer token via `Authorization: Bearer <apiKey>` header

### Paper Routing & Edge Cases
- **Destination folder:** ~/Documents/Papers, auto-created on first classified paper if it doesn't exist
- **Duplicate handling:** If a file with the same filename already exists in ~/Documents/Papers, delete the duplicate from ~/Downloads (the paper is already archived)
- **Password-protected PDFs:** Skip classification - can't extract text, leave in Downloads
- **File size limit:** No size limit - full text is sent to the LLM
- **Original file:** Move (not copy) the PDF from ~/Downloads to ~/Documents/Papers on positive classification

### Claude's Discretion
- Classification prompt design (system prompt + user message structure)
- Text cleanup implementation details
- HTTP client implementation for OpenAI API
- Error message wording for menu bar API key guidance
- JSON response parsing strategy for the binary classification

</decisions>

<specifics>
## Specific Ideas

- OpenAI API uses `https://api.openai.com/v1/chat/completions` with Bearer token authentication
- Config needs `pdf.openaiApiKey` (string, user-provided) and `pdf.openaiModel` (string, defaults to "gpt-4o")
- Config keeps `pdf.destinationPath: "~/Documents/Papers"` from default-config.json
- Phase 1's FileWatcher already detects new files in ~/Downloads - this phase adds PDF routing alongside audio routing in AppCoordinator
- The menu bar guidance pattern for missing API key mirrors the ffmpeg guidance from Phase 3

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

</deferred>

---

*Phase: 04-pdf-classification*
*Context gathered: 2026-02-22*
