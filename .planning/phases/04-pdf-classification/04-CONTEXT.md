# Phase 4: PDF Classification - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Classify PDF files in ~/Downloads as scientific papers using the local LM Studio LLM and route them to ~/Documents/Papers; leave non-papers untouched. This phase builds on Phase 1's file watcher and config infrastructure to add a second file processing pipeline alongside the audio pipeline.

**Requirements:** PDF-01, PDF-02, PDF-03, PDF-04

</domain>

<decisions>
## Implementation Decisions

### Text Extraction Strategy
- **Extraction approach:** Heuristically identify and extract the abstract/intro section from the PDF first; if abstract detection fails (unconventional formatting), fall back to extracting the first 2-3 pages of text
- **PDF metadata inclusion:** Include PDF document attributes (title, author, subject) from PDFKit alongside extracted body text when sending to the LLM
- **Text cleanup:** Apply basic cleanup before sending — strip headers, footers, page numbers, and excessive whitespace
- **Token cap:** Cap extracted text at ~2000 tokens (~1500 words) to keep prompts fast and within reasonable context size
- **Scanned/image PDFs:** If no text can be extracted (image-only PDFs), skip classification entirely, leave in Downloads, and log a warning
- **Language:** Classify regardless of language — a scientific paper is a scientific paper whether in English, Italian, German, etc.

### LLM Classification Behavior
- **Response format:** Binary yes/no classification (is_paper: true/false) — no confidence scores or reasoning
- **Ambiguous results:** Conservative approach — if classification is uncertain or the LLM response can't be parsed, leave the PDF in Downloads (better to miss a paper than misfile a receipt)
- **Paper definition:** Broad — any academic/research document qualifies (peer-reviewed articles, preprints, conference papers, theses, dissertations, technical reports)
- **Prompt design:** Claude's discretion — design an effective system prompt and user prompt for binary scientific paper classification

### LM Studio Connectivity
- **API endpoint:** OpenAI-compatible chat completions (/v1/chat/completions)
- **Model selection:** Configurable model name in config.json — user specifies which loaded model to use
- **Request timeout:** 30 seconds per classification request
- **Retry strategy:** 3 retries (4 total attempts) with exponential backoff (2s, 4s, 8s) before giving up on a single PDF
- **Failure behavior:** After all retries exhausted, leave PDF in Downloads and log the failure
- **Startup behavior:** Show a persistent menu bar message when LM Studio is not reachable (similar to ffmpeg guidance in Phase 3) AND periodically poll in the background
- **Health polling:** Check LM Studio availability every 60 seconds when it's unreachable; once available, dismiss the menu bar guidance and begin processing queued PDFs
- **Port configuration:** Use `pdf.lmStudioPort` from config (default: 1234)

### Paper Routing & Edge Cases
- **Destination folder:** ~/Documents/Papers, auto-created on first classified paper if it doesn't exist
- **Duplicate handling:** If a file with the same filename already exists in ~/Documents/Papers, skip the move (don't overwrite, don't rename)
- **Password-protected PDFs:** Skip classification — can't extract text, leave in Downloads
- **File size limit:** No size limit — the text extraction token cap handles large PDFs naturally
- **Original file:** Move (not copy) the PDF from ~/Downloads to ~/Documents/Papers on positive classification

### Claude's Discretion
- Classification prompt design (system prompt + user message structure)
- Abstract detection heuristics (keyword matching, section boundaries, etc.)
- Text cleanup implementation details
- HTTP client implementation for LM Studio API
- LM Studio health check mechanism
- Error message wording for menu bar LM Studio guidance
- JSON response parsing strategy for the binary classification

</decisions>

<specifics>
## Specific Ideas

- LM Studio exposes an OpenAI-compatible API at `http://localhost:{port}/v1/chat/completions` by default
- Config already has `pdf.lmStudioPort: 1234` and `pdf.destinationPath: "~/Documents/Papers"` in default-config.json
- Need to add `pdf.modelName` to config for the configurable model selection
- Phase 1's FileWatcher already detects new files in ~/Downloads — this phase adds PDF routing alongside audio routing in AppCoordinator
- The menu bar guidance pattern for LM Studio availability mirrors the ffmpeg guidance from Phase 3

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 04-pdf-classification*
*Context gathered: 2026-02-22*
