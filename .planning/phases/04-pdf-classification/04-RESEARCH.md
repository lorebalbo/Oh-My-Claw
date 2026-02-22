# Phase 4: PDF Classification - Research

**Researched:** 2026-02-22
**Phase:** 04-pdf-classification
**Requirements:** PDF-01, PDF-02, PDF-03, PDF-04

---

## 1. User Constraints (from CONTEXT.md - verbatim)

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

---

## 2. Phase Requirements Mapping

| Requirement | Description | Implementation Approach | Key Research Findings |
|-------------|-------------|------------------------|----------------------|
| **PDF-01** | App detects PDF files in ~/Downloads | `PDFFileIdentifier` struct using UTType `.pdf` conformance check (mirrors `AudioFileIdentifier` dual-gate pattern) | UTType(filenameExtension: "pdf") conforms to `.pdf`. Single extension ("pdf") simplifies identifier vs. audio's 7 extensions. |
| **PDF-02** | App sends PDF content to OpenAI API for scientific paper classification | `OpenAIClient` struct using URLSession async/await to POST to `https://api.openai.com/v1/chat/completions`. `PDFTextExtractor` uses PDFKit for text. | URLSession.shared.data(for:) with async/await. JSON Codable models for ChatCompletion request/response. Bearer token authentication. |
| **PDF-03** | Classified papers are moved to ~/Documents/Papers | `PDFTask.process()` moves file via FileManager after positive classification | Mirror AudioTask's move logic: createDirectory(withIntermediateDirectories:), check existing, moveItem. |
| **PDF-04** | Non-paper PDFs are left in Downloads untouched | `PDFTask.process()` returns `.skipped` for non-papers, errors, and unparseable responses | Conservative: any non-`true` result = skip. No false-positive risk. |

---

## 3. Standard Stack

### PDFKit (Apple Framework)

PDFKit is a built-in macOS framework (`import PDFKit`) - no dependencies required. Available since macOS 10.4, fully supported on all target versions.

**Key types:**
- `PDFDocument` - represents a PDF file. Init with `PDFDocument(url: URL)`. Returns `nil` if the file can't be opened.
- `PDFPage` - a single page. Access via `document.page(at: index)` (0-based).
- `PDFDocument.pageCount` - total number of pages.
- `PDFDocument.documentAttributes` - dictionary with keys like `PDFDocumentAttribute.titleAttribute`, `.authorAttribute`, `.subjectAttribute`.
- `PDFPage.string` - all text content on a page as a single String (or nil if no text layer).
- `PDFDocument.isLocked` - `true` if the PDF is password-protected and not yet unlocked.

**Text extraction pattern:**
```swift
import PDFKit

func extractText(from url: URL) -> String? {
    guard let document = PDFDocument(url: url) else { return nil }
    guard !document.isLocked else { return nil }

    var pages: [String] = []
    for i in 0..<document.pageCount {
        if let page = document.page(at: i),
           let text = page.string {
            pages.append(text)
        }
    }

    let fullText = pages.joined(separator: "\n")
    return fullText.isEmpty ? nil : fullText
}
```

**Metadata extraction:**
```swift
func extractMetadata(from document: PDFDocument) -> (title: String?, author: String?, subject: String?) {
    let attrs = document.documentAttributes
    let title = attrs?[PDFDocumentAttribute.titleAttribute] as? String
    let author = attrs?[PDFDocumentAttribute.authorAttribute] as? String
    let subject = attrs?[PDFDocumentAttribute.subjectAttribute] as? String
    return (title, author, subject)
}
```

**Image-only detection:** If `page.string` returns `nil` or an empty/whitespace-only string for all pages, the PDF is image-only (scanned). No text layer = skip classification.

### URLSession (Foundation)

Use Foundation's built-in `URLSession` with async/await - no third-party HTTP libraries needed.

**Request construction for OpenAI API:**
```swift
func buildRequest(url: URL, body: Data, apiKey: String, timeout: TimeInterval) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = body
    request.timeoutInterval = timeout
    return request
}
```

**Async data call:**
```swift
let (data, response) = try await URLSession.shared.data(for: request)
guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200 else {
    throw OpenAIError.badResponse
}
let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
```

### JSON Codable Models for OpenAI API

**Request model:**
```swift
struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int

    struct ChatMessage: Encodable {
        let role: String  // "system" or "user"
        let content: String
    }
}
```

**Response model:**
```swift
struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}
```

OpenAI API at `https://api.openai.com/v1/chat/completions` uses Bearer token authentication. The `model` field specifies which model to use (e.g., `"gpt-4o"`).

---

## 4. Architecture Patterns (Mirroring Existing Codebase)

### Pattern 1: FileTask Protocol Conformance (mirror AudioTask)

`PDFTask` conforms to `FileTask` exactly as `AudioTask` does:

```swift
struct PDFTask: FileTask, Sendable {
    let id = "pdf"
    let displayName = "PDF Classification"
    let isEnabled: Bool

    func canHandle(file: URL) -> Bool { /* UTType check */ }
    func process(file: URL) async throws -> TaskResult { /* pipeline */ }
}
```

**Key point:** `PDFTask` is registered in `AppCoordinator.tasks` array alongside `AudioTask`. The event loop in `startMonitoring()` already iterates all tasks - zero changes to routing logic needed.

### Pattern 2: File Identifier (mirror AudioFileIdentifier)

`PDFFileIdentifier` follows `AudioFileIdentifier`'s dual-gate approach:

```swift
struct PDFFileIdentifier: Sendable {
    func isRecognizedPDFFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "pdf" else { return false }
        guard let utType = UTType(filenameExtension: ext),
              utType.conforms(to: .pdf) else { return false }
        return true
    }
}
```

### Pattern 3: External Service Client (mirror FFmpegService)

`OpenAIClient` follows the FFmpegService decomposition pattern:
- **Health check -> API key validation:** Verify that `openaiApiKey` is non-empty at launch. No network health check needed - OpenAI is a cloud service.
- **Converter -> Classifier:** Instead of `FFmpegConverter.convert()` (input->output), use `OpenAIClient.classify(text:)` (text->bool).
- **Error types:** Define `OpenAIError` enum: `.missingApiKey`, `.badResponse(statusCode:)`, `.emptyResponse`, `.decodingFailed(String)`.

```swift
struct OpenAIClient: Sendable {
    let apiKey: String
    let modelName: String
    let timeout: TimeInterval

    func classify(text: String) async throws -> Bool { /* POST /v1/chat/completions */ }
}
```

### Pattern 4: AppCoordinator Integration (mirror AudioTask wiring)

In `AppCoordinator.start()`, the PDF pipeline is wired identically to audio:
1. Read `store.config.pdf` for PDFConfig
2. Create dependencies: `PDFFileIdentifier()`, `PDFTextExtractor()`, `OpenAIClient(...)`
3. Create `PDFTask(identifier:, textExtractor:, client:, config:)`
4. If `pdfConfig.enabled`: `tasks.append(pdfTask)`
5. Check if API key is configured -> set `appState.openaiApiKeyConfigured`
6. If not configured, show menu bar guidance

### Pattern 5: Menu Bar Guidance (mirror ffmpeg guidance from Phase 3)

- `AppState` adds: `var openaiApiKeyConfigured: Bool = true`
- `MenuBarView` shows guidance when `!coordinator.appState.openaiApiKeyConfigured`
- Directs user to add their OpenAI API key to config.json

### Pattern 6: Config Extension

`PDFConfig` needs `openaiApiKey` and `openaiModel` fields:

```swift
struct PDFConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var openaiApiKey: String
    var openaiModel: String
    var destinationPath: String

    static let defaults = PDFConfig(
        enabled: true,
        openaiApiKey: "",  // User must configure
        openaiModel: "gpt-4o",
        destinationPath: "~/Documents/Papers"
    )
}
```

---

## 5. Don't Hand-Roll

| Component | Use Instead | Why |
|-----------|-------------|-----|
| PDF text extraction | `PDFKit` (PDFDocument, PDFPage.string) | Built-in macOS framework, handles all PDF encodings, no dependencies |
| HTTP client | `URLSession` async/await | Built-in Foundation, no need for Alamofire or similar |
| JSON encoding/decoding | `Codable` (JSONEncoder/JSONDecoder) | Swift standard, type-safe, zero overhead |
| PDF type detection | `UTType(.pdf)` from UniformTypeIdentifiers | Same pattern as AudioFileIdentifier |
| Retry with backoff | Simple for-loop with `Task.sleep(nanoseconds:)` | No need for a retry library |

---

## 6. Common Pitfalls

### PDFKit Pitfalls

1. **PDFDocument init returns nil, not throws.** Always handle `guard let document = PDFDocument(url:)`.

2. **PDFPage.string may contain garbage for complex layouts.** Multi-column academic papers can produce interleaved text. Acceptable - GPT-4o can handle it.

3. **PDFDocument.isLocked must be checked before accessing pages.** A locked document's pages return nil strings.

4. **PDFKit is NOT thread-safe.** Do all PDFKit work in a single synchronous block, extract the text as a String, then pass the String to async operations.

5. **documentAttributes dictionary uses specific key types.** Keys are `PDFDocumentAttribute` values, not arbitrary strings. Values are `Any` - cast to `String`.

### URLSession / OpenAI API Pitfalls

6. **API key must be non-empty.** Validate at launch and show guidance if missing.

7. **OpenAI rate limits.** 429 response means rate-limited. Exponential backoff handles this naturally.

8. **Response JSON may have unexpected structure.** The `choices` array could be empty. Always check `choices.first?.message.content`.

9. **URLSession timeout vs. API inference time.** Set `request.timeoutInterval = 60`. Cloud API calls can take longer than local inference.

10. **Exponential backoff must use Task.sleep, not Thread.sleep.** `Thread.sleep` blocks the thread; `Task.sleep(nanoseconds:)` suspends cooperatively.

### Pipeline Pitfalls

11. **File may disappear between detection and processing.** PDFTask should guard against it when opening the PDFDocument.

12. **Race condition: two PDFs with the same name arrive quickly.** The duplicate check handles this - second one is deleted.

13. **Empty API key in config.** Show a menu bar warning and skip PDF classification entirely until configured.

---

## 7. Code Examples

### OpenAIClient - Full Implementation Pattern

```swift
import Foundation

enum OpenAIError: Error, Sendable {
    case missingApiKey
    case badResponse(statusCode: Int)
    case emptyResponse
    case decodingFailed(String)
}

struct OpenAIClient: Sendable {
    let apiKey: String
    let modelName: String
    let timeout: TimeInterval

    private static let baseURL = URL(string: "https://api.openai.com/v1")!

    init(apiKey: String, modelName: String, timeout: TimeInterval = 60) {
        self.apiKey = apiKey
        self.modelName = modelName
        self.timeout = timeout
    }

    func classify(text: String) async throws -> Bool {
        guard !apiKey.isEmpty else { throw OpenAIError.missingApiKey }

        let url = Self.baseURL.appendingPathComponent("chat/completions")

        let systemPrompt = """
            You are a document classifier. Determine whether the following document \
            is a scientific or academic paper.

            Respond with ONLY a JSON object: {"is_paper": true} or {"is_paper": false}. \
            No other text.

            Classify as a scientific paper ONLY if the document contains most of these: \
            an abstract, numbered sections, citations in the text, a references/bibliography \
            section, and author affiliations with research institutions or universities.

            Do NOT classify as a paper: GitHub issues, bug reports, invoices, receipts, \
            manuals, product docs, legal documents, forms, newsletters, blog posts, \
            slide decks, or general technical documentation.

            If you are unsure, respond {"is_paper": false}.
            """

        let requestBody = ChatCompletionRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text)
            ],
            temperature: 0.0,
            max_tokens: 50
        )

        let bodyData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenAIError.badResponse(statusCode: statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIError.emptyResponse
        }

        return parseClassification(content)
    }

    private func parseClassification(_ response: String) -> Bool {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let data = trimmed.data(using: .utf8),
           let result = try? JSONDecoder().decode(ClassificationResult.self, from: data) {
            return result.is_paper
        }

        if trimmed.contains("\"is_paper\": true") || trimmed.contains("\"is_paper\":true") {
            return true
        }

        return false
    }

    static func classifyWithRetry(
        text: String,
        client: OpenAIClient,
        maxRetries: Int = 3
    ) async -> Bool? {
        let backoffSeconds: [UInt64] = [2, 4, 8]

        for attempt in 0...maxRetries {
            do {
                return try await client.classify(text: text)
            } catch {
                AppLogger.shared.warn("Classification attempt failed",
                    context: ["attempt": "\(attempt + 1)/\(maxRetries + 1)", "error": "\(error)"])

                if attempt < maxRetries {
                    let delay = backoffSeconds[min(attempt, backoffSeconds.count - 1)]
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                }
            }
        }

        return nil
    }
}
```

### PDFTask Pipeline - Full Pattern

```swift
struct PDFTask: FileTask, Sendable {
    let id = "pdf"
    let displayName = "PDF Classification"
    let isEnabled: Bool

    private static let minimumPaperPages = 2

    private let identifier: PDFFileIdentifier
    private let textExtractor: PDFTextExtractor
    private let client: OpenAIClient
    private let destinationPath: String

    func canHandle(file: URL) -> Bool {
        identifier.isRecognizedPDFFile(file)
    }

    func process(file: URL) async throws -> TaskResult {
        guard let extraction = textExtractor.extract(from: file) else {
            return .skipped(reason: "No extractable text (image-only or protected)")
        }

        if extraction.pageCount < Self.minimumPaperPages {
            return .skipped(reason: "Only \(extraction.pageCount) page(s) - not a paper")
        }

        guard let isPaper = await OpenAIClient.classifyWithRetry(
            text: extraction.text,
            client: client,
            maxRetries: 3
        ) else {
            return .skipped(reason: "Classification failed - leaving in Downloads")
        }

        guard isPaper else {
            return .skipped(reason: "Not classified as a scientific paper")
        }

        let expandedPath = NSString(string: destinationPath).expandingTildeInPath
        let destDir = URL(fileURLWithPath: expandedPath, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destination = destDir.appendingPathComponent(file.lastPathComponent)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: file)
            return .processed(action: "Duplicate deleted from Downloads - already in Papers")
        }

        try FileManager.default.moveItem(at: file, to: destination)
        return .processed(action: "Classified as paper, moved to ~/Documents/Papers")
    }
}
```

---

## 8. Sources

| Source | What It Confirms |
|--------|-----------------|
| Apple PDFKit Documentation (developer.apple.com/documentation/pdfkit) | PDFDocument, PDFPage.string, documentAttributes, isLocked API |
| Apple URLSession Documentation (developer.apple.com/documentation/foundation/urlsession) | async/await data(for:) API, URLRequest configuration |
| OpenAI API Reference (platform.openai.com/docs/api-reference/chat) | Request/response JSON schema, Bearer token auth, model selection |
| Existing codebase: AudioFileIdentifier.swift | Dual-gate UTType pattern for file identification |
| Existing codebase: AudioTask.swift | FileTask pipeline pattern (canHandle -> process -> TaskResult) |
| Existing codebase: FFmpegService.swift | External service integration pattern |
| Existing codebase: AppCoordinator.swift | Task registration, event routing, service wiring at startup |
| Existing codebase: Phase 3 Plan 03-03 | Menu bar guidance pattern (AppState flag + conditional MenuBarView section) |

---

*Research completed: 2026-02-22*
*Phase: 04-pdf-classification*
