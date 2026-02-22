# Phase 4: PDF Classification — Research

**Researched:** 2026-02-22
**Phase:** 04-pdf-classification
**Requirements:** PDF-01, PDF-02, PDF-03, PDF-04

---

## 1. User Constraints (from CONTEXT.md — verbatim)

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

---

## 2. Phase Requirements Mapping

| Requirement | Description | Implementation Approach | Key Research Findings |
|-------------|-------------|------------------------|----------------------|
| **PDF-01** | App detects PDF files in ~/Downloads | `PDFFileIdentifier` struct using UTType `.pdf` conformance check (mirrors `AudioFileIdentifier` dual-gate pattern) | UTType(filenameExtension: "pdf") conforms to `.pdf`. Single extension ("pdf") simplifies identifier vs. audio's 7 extensions. |
| **PDF-02** | App sends PDF content to LM Studio local API for scientific paper classification | `LMStudioClient` struct using URLSession async/await to POST to `http://localhost:{port}/v1/chat/completions`. `PDFTextExtractor` uses PDFKit for text. | URLSession.shared.data(for:) with async/await. JSON Codable models for ChatCompletion request/response. PDFDocument(url:).page(at:)?.string. |
| **PDF-03** | Classified papers are moved to ~/Documents/Papers | `PDFTask.process()` moves file via FileManager after positive classification | Mirror AudioTask's move logic: createDirectory(withIntermediateDirectories:), check existing, moveItem. |
| **PDF-04** | Non-paper PDFs are left in Downloads untouched | `PDFTask.process()` returns `.skipped` for non-papers, errors, and unparseable responses | Conservative: any non-`true` result = skip. No false-positive risk. |

---

## 3. Standard Stack

### PDFKit (Apple Framework)

PDFKit is a built-in macOS framework (`import PDFKit`) — no dependencies required. Available since macOS 10.4, fully supported on all target versions.

**Key types:**
- `PDFDocument` — represents a PDF file. Init with `PDFDocument(url: URL)`. Returns `nil` if the file can't be opened.
- `PDFPage` — a single page. Access via `document.page(at: index)` (0-based).
- `PDFDocument.pageCount` — total number of pages.
- `PDFDocument.documentAttributes` — dictionary with keys like `PDFDocumentAttribute.titleAttribute`, `.authorAttribute`, `.subjectAttribute`.
- `PDFPage.string` — all text content on a page as a single String (or nil if no text layer).
- `PDFDocument.isLocked` — `true` if the PDF is password-protected and not yet unlocked.

**Text extraction pattern:**
```swift
import PDFKit

func extractText(from url: URL) -> String? {
    guard let document = PDFDocument(url: url) else { return nil }
    
    // Password-protected check
    guard !document.isLocked else { return nil }
    
    // Extract text page by page
    var pages: [String] = []
    let pageLimit = min(document.pageCount, 3)
    for i in 0..<pageLimit {
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

Use Foundation's built-in `URLSession` with async/await — no third-party HTTP libraries needed.

**Request construction:**
```swift
func buildRequest(url: URL, body: Data, timeout: TimeInterval) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
    throw LMStudioError.badResponse
}
let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
```

### JSON Codable Models for OpenAI-Compatible API

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

LM Studio's `/v1/chat/completions` endpoint returns the same JSON schema as OpenAI's API. The `model` field in the request must match a model loaded in LM Studio (e.g., `"lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF"`).

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

**Key point:** `PDFTask` is registered in `AppCoordinator.tasks` array alongside `AudioTask`. The event loop in `startMonitoring()` already iterates all tasks — zero changes to routing logic needed. The first task that returns `canHandle == true` processes the file.

### Pattern 2: File Identifier (mirror AudioFileIdentifier)

`PDFFileIdentifier` follows `AudioFileIdentifier`'s dual-gate approach — check extension first, then confirm UTI:

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

`LMStudioClient` follows the FFmpegService decomposition pattern:
- **Locator → Health check:** Instead of `FFmpegLocator.locate()` (one-time binary search), use a health check against `GET /v1/models` to verify LM Studio is running.
- **Converter → Classifier:** Instead of `FFmpegConverter.convert()` (input→output), use `LMStudioClient.classify(text:metadata:)` (text→bool).
- **Error types:** Define `LMStudioError` enum (mirrors `ConversionError`): `.unreachable`, `.badResponse`, `.timeout`, `.classificationFailed`.

```swift
struct LMStudioClient: Sendable {
    let baseURL: URL
    let modelName: String
    let timeout: TimeInterval
    
    func isAvailable() async -> Bool { /* GET /v1/models */ }
    func classify(text: String, metadata: PDFMetadata) async throws -> Bool { /* POST /v1/chat/completions */ }
}
```

### Pattern 4: AppCoordinator Integration (mirror AudioTask wiring)

In `AppCoordinator.start()`, the PDF pipeline is wired identically to audio:
1. Read `store.config.pdf` for PDFConfig
2. Create dependencies: `PDFFileIdentifier()`, `PDFTextExtractor()`, `LMStudioClient(...)`
3. Create `PDFTask(identifier:, textExtractor:, client:, config:)`
4. If `pdfConfig.enabled`: `tasks.append(pdfTask)`
5. Check LM Studio availability → set `appState.lmStudioAvailable`
6. If unavailable, start background health polling task

### Pattern 5: Menu Bar Guidance (mirror ffmpeg guidance from Phase 3)

The Phase 3 plan establishes the pattern: `AppState` gets a boolean flag (`ffmpegAvailable`), and `MenuBarView` shows a conditional `VStack` with warning icon + guidance text. For PDF:

- `AppState` adds: `var lmStudioAvailable: Bool = true`
- `MenuBarView` shows guidance when `!coordinator.appState.lmStudioAvailable`
- **Key difference from ffmpeg:** LM Studio availability is polled every 60s (not just at launch). When it becomes available, dismiss the message and process queued PDFs. This requires a background `Task` in `AppCoordinator` that periodically checks and updates `appState.lmStudioAvailable`.

### Pattern 6: Config Extension

`PDFConfig` already exists in `AppConfig.swift` with `enabled`, `lmStudioPort`, and `destinationPath`. Add `modelName: String` field:

```swift
struct PDFConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var lmStudioPort: Int
    var modelName: String
    var destinationPath: String

    static let defaults = PDFConfig(
        enabled: true,
        lmStudioPort: 1234,
        modelName: "",  // User must configure — empty means "use whatever is loaded"
        destinationPath: "~/Documents/Papers"
    )
}
```

Update `default-config.json` to include `"modelName": ""`.

---

## 5. Don't Hand-Roll

| Component | Use Instead | Why |
|-----------|-------------|-----|
| PDF text extraction | `PDFKit` (PDFDocument, PDFPage.string) | Built-in macOS framework, handles all PDF encodings, no dependencies |
| HTTP client | `URLSession` async/await | Built-in Foundation, no need for Alamofire or similar |
| JSON encoding/decoding | `Codable` (JSONEncoder/JSONDecoder) | Swift standard, type-safe, zero overhead |
| PDF type detection | `UTType(.pdf)` from UniformTypeIdentifiers | Same pattern as AudioFileIdentifier — system-level type resolution |
| Token counting / word splitting | Simple `components(separatedBy:).count` word count | Exact tokenization is unnecessary — ~1500 words ≈ ~2000 tokens is close enough for a cap |
| Retry with backoff | Simple for-loop with `Task.sleep(nanoseconds:)` | No need for a retry library — 3 retries with 2/4/8s delays is trivial |
| Periodic health polling | `Task` + `while !Task.isCancelled` + `Task.sleep` loop | Built-in structured concurrency handles cancellation cleanly |

---

## 6. Common Pitfalls

### PDFKit Pitfalls

1. **PDFDocument init returns nil, not throws.** Always handle `guard let document = PDFDocument(url:)` — corrupt or unreadable PDFs silently return nil.

2. **PDFPage.string may contain garbage for complex layouts.** Multi-column academic papers can produce interleaved text. This is acceptable — the LLM can handle imperfect text extraction. Don't attempt layout-aware extraction; it's not worth the complexity.

3. **PDFDocument.isLocked must be checked before accessing pages.** A locked document's pages return nil strings. Check `isLocked` first and skip if true.

4. **PDFKit is NOT thread-safe.** PDFDocument and PDFPage are not Sendable. Create and use them on the same thread/task. In an async context, do all PDFKit work in a single synchronous block, extract the text as a String, then pass the String (which is Sendable) to subsequent async operations.

5. **documentAttributes dictionary uses specific key types.** Keys are `PDFDocumentAttribute` values (e.g., `.titleAttribute`), not arbitrary strings. Values are `Any` — cast to `String`.

### URLSession / LM Studio Pitfalls

6. **LM Studio may not be running.** URLSession throws `URLError(.cannotConnectToHost)` when the server is down. Catch this specifically for the health check — don't treat it as a classification failure that needs retrying.

7. **LM Studio model name mismatch.** If the `model` field in the request doesn't match a loaded model, LM Studio returns a 400 or 404. The error message in the response body will say which models are available. Log this clearly.

8. **Response JSON may have unexpected structure.** Even with the OpenAI-compatible API, the `choices` array could be empty if the model fails to generate. Always check `choices.first?.message.content` and handle nil.

9. **URLSession timeout vs. LLM inference time.** Set `request.timeoutInterval = 30` explicitly. Default URLSession timeout is 60s, which is too long. The 30s timeout per user decision ensures the app doesn't hang.

10. **Exponential backoff must use Task.sleep, not Thread.sleep.** `Thread.sleep` blocks the thread; `Task.sleep(nanoseconds:)` suspends cooperatively.

### Pipeline Pitfalls

11. **File may disappear between detection and processing.** AppCoordinator already handles this (checks `fileURL.fileExists`), but PDFTask should also guard against it when opening the PDFDocument.

12. **Race condition: two PDFs with the same name arrive quickly.** The duplicate check (same filename in destination) handles this — second one is skipped. No additional locking needed.

13. **Empty model name in config.** If the user hasn't configured `pdf.modelName`, either use it as-is (LM Studio uses the currently loaded model when model field is empty/missing) or log a warning. LM Studio typically accepts an empty model field and uses whatever is loaded.

14. **Health check endpoint.** Use `GET /v1/models` for health checking — it's lightweight, returns quickly, and confirms LM Studio is actually serving (not just TCP-listening). A simple TCP connect check would miss cases where LM Studio is starting up.

---

## 7. Code Examples

### PDFTextExtractor — Full Implementation Pattern

```swift
import PDFKit

struct PDFMetadata: Sendable {
    let title: String?
    let author: String?
    let subject: String?
}

struct PDFTextExtractor: Sendable {
    private let maxWords = 1500
    private let fallbackPageCount = 3
    
    /// Extract text and metadata from a PDF file.
    /// Returns nil if the PDF can't be opened, is locked, or has no text.
    func extract(from url: URL) -> (text: String, metadata: PDFMetadata)? {
        // PDFKit is not thread-safe — all work in one synchronous block
        guard let document = PDFDocument(url: url) else { return nil }
        guard !document.isLocked else { return nil }
        
        // Extract metadata
        let attrs = document.documentAttributes
        let metadata = PDFMetadata(
            title: attrs?[PDFDocumentAttribute.titleAttribute] as? String,
            author: attrs?[PDFDocumentAttribute.authorAttribute] as? String,
            subject: attrs?[PDFDocumentAttribute.subjectAttribute] as? String
        )
        
        // Try abstract detection first
        let firstPageText = document.page(at: 0)?.string ?? ""
        if let abstractText = extractAbstract(from: firstPageText) {
            let cleaned = cleanup(abstractText)
            let capped = capWords(cleaned, max: maxWords)
            return capped.isEmpty ? nil : (text: capped, metadata: metadata)
        }
        
        // Fallback: extract first N pages
        var pages: [String] = []
        let limit = min(document.pageCount, fallbackPageCount)
        for i in 0..<limit {
            if let page = document.page(at: i),
               let text = page.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(text)
            }
        }
        
        let fullText = pages.joined(separator: "\n")
        let cleaned = cleanup(fullText)
        let capped = capWords(cleaned, max: maxWords)
        return capped.isEmpty ? nil : (text: capped, metadata: metadata)
    }
    
    // MARK: - Abstract Detection
    
    /// Attempt to find and extract the abstract section from raw page text.
    private func extractAbstract(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var abstractStart: Int?
        var abstractEnd: Int?
        
        let abstractMarkers = ["abstract", "summary", "résumé", "zusammenfassung", "riassunto"]
        let sectionEndMarkers = [
            "introduction", "1.", "1 ", "keywords", "key words",
            "i.", "i ", "background"
        ]
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            
            // Find abstract header
            if abstractStart == nil {
                if abstractMarkers.contains(where: { trimmed.hasPrefix($0) }) {
                    abstractStart = index + 1  // Start from line after the header
                }
            } else {
                // Find section after abstract
                if sectionEndMarkers.contains(where: { trimmed.hasPrefix($0) }) {
                    abstractEnd = index
                    break
                }
            }
        }
        
        guard let start = abstractStart else { return nil }
        let end = abstractEnd ?? min(start + 30, lines.count)  // Cap at ~30 lines if no end marker
        
        let abstractLines = lines[start..<end]
        let abstract = abstractLines.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only return if we got meaningful content (at least 50 chars)
        return abstract.count >= 50 ? abstract : nil
    }
    
    // MARK: - Text Cleanup
    
    private func cleanup(_ text: String) -> String {
        var result = text
        
        // Collapse multiple whitespace/newlines into single spaces
        result = result.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        
        // Strip common page number patterns (standalone numbers on a line)
        result = result.replacingOccurrences(
            of: "\\b\\d{1,4}\\b(?=\\s|$)",
            with: "",
            options: .regularExpression
        )
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func capWords(_ text: String, max: Int) -> String {
        let words = text.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if words.count <= max { return text }
        return words.prefix(max).joined(separator: " ")
    }
}
```

### LMStudioClient — Full Implementation Pattern

```swift
import Foundation

enum LMStudioError: Error, Sendable {
    case unreachable
    case badResponse(statusCode: Int)
    case emptyResponse
    case decodingFailed(String)
}

struct LMStudioClient: Sendable {
    let baseURL: URL       // http://localhost:1234/v1
    let modelName: String  // Configurable model identifier
    let timeout: TimeInterval  // 30s
    
    init(port: Int, modelName: String, timeout: TimeInterval = 30) {
        self.baseURL = URL(string: "http://localhost:\(port)/v1")!
        self.modelName = modelName
        self.timeout = timeout
    }
    
    // MARK: - Health Check
    
    /// Check if LM Studio is running and responding.
    /// Uses GET /v1/models — lightweight, confirms serving status.
    func isAvailable() async -> Bool {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5  // Quick check, don't wait long
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }
    
    // MARK: - Classification
    
    /// Classify whether the given text represents a scientific paper.
    /// Returns true (is a paper) or false (not a paper).
    func classify(text: String, metadata: PDFMetadata) async throws -> Bool {
        let url = baseURL.appendingPathComponent("chat/completions")
        
        // Build prompt
        let systemPrompt = """
        You are a document classifier. Your task is to determine whether a document \
        is a scientific/academic paper. Respond with ONLY a JSON object: {"is_paper": true} \
        or {"is_paper": false}. No other text.
        
        A scientific paper includes: peer-reviewed articles, preprints, conference papers, \
        theses, dissertations, and technical reports from academic or research institutions. \
        Papers may be in any language.
        
        If you are unsure, respond with {"is_paper": false}.
        """
        
        var userContent = ""
        if let title = metadata.title { userContent += "Title: \(title)\n" }
        if let author = metadata.author { userContent += "Author: \(author)\n" }
        if let subject = metadata.subject { userContent += "Subject: \(subject)\n" }
        userContent += "\nDocument text:\n\(text)"
        
        let requestBody = ChatCompletionRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userContent)
            ],
            temperature: 0.0,
            max_tokens: 20  // Only need {"is_paper": true/false}
        )
        
        let bodyData = try JSONEncoder().encode(requestBody)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = timeout
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LMStudioError.badResponse(statusCode: statusCode)
        }
        
        let completionResponse = try JSONDecoder().decode(
            ChatCompletionResponse.self, from: data
        )
        
        guard let content = completionResponse.choices.first?.message.content else {
            throw LMStudioError.emptyResponse
        }
        
        return parseClassification(content)
    }
    
    /// Parse LLM response into a boolean classification.
    /// Conservative: returns false for anything that isn't clearly true.
    private func parseClassification(_ response: String) -> Bool {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Try JSON parsing first: {"is_paper": true}
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONDecoder().decode(ClassificationResult.self, from: data) {
            return json.is_paper
        }
        
        // Fallback: look for "true" in the response
        // Conservative: only return true if we're confident
        if trimmed.contains("\"is_paper\": true") || trimmed.contains("\"is_paper\":true") {
            return true
        }
        
        // Anything else: conservative false
        return false
    }
}

// MARK: - API Models

struct ChatCompletionRequest: Encodable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
    
    struct ChatMessage: Encodable, Sendable {
        let role: String
        let content: String
    }
}

struct ChatCompletionResponse: Decodable, Sendable {
    let choices: [Choice]
    
    struct Choice: Decodable, Sendable {
        let message: Message
    }
    
    struct Message: Decodable, Sendable {
        let content: String
    }
}

struct ClassificationResult: Decodable, Sendable {
    let is_paper: Bool
}
```

### Retry with Exponential Backoff Pattern

```swift
/// Attempt classification with retries and exponential backoff.
/// Returns nil if all attempts fail (conservative: treat as non-paper).
func classifyWithRetry(
    text: String,
    metadata: PDFMetadata,
    client: LMStudioClient,
    maxRetries: Int = 3
) async -> Bool? {
    let backoffSeconds: [UInt64] = [2, 4, 8]
    
    for attempt in 0...maxRetries {
        do {
            return try await client.classify(text: text, metadata: metadata)
        } catch {
            AppLogger.shared.warn("Classification attempt \(attempt + 1) failed",
                context: ["error": "\(error)"])
            
            if attempt < maxRetries {
                let delay = backoffSeconds[attempt]
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
    }
    
    return nil  // All retries exhausted
}
```

### Health Polling Pattern

```swift
/// Background task that polls LM Studio availability every 60 seconds.
/// Updates appState.lmStudioAvailable and processes queued PDFs when available.
private func startHealthPolling(client: LMStudioClient) {
    healthPollingTask = Task { [weak self] in
        while !Task.isCancelled {
            let available = await client.isAvailable()
            await MainActor.run {
                self?.appState.lmStudioAvailable = available
            }
            if available {
                AppLogger.shared.info("LM Studio is available")
                break  // Stop polling, begin normal operation
            }
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        }
    }
}
```

### PDFTask Pipeline — Full Pattern

```swift
struct PDFTask: FileTask, Sendable {
    let id = "pdf"
    let displayName = "PDF Classification"
    let isEnabled: Bool
    
    private let identifier: PDFFileIdentifier
    private let textExtractor: PDFTextExtractor
    private let client: LMStudioClient
    private let config: PDFConfig
    
    func canHandle(file: URL) -> Bool {
        identifier.isRecognizedPDFFile(file)
    }
    
    func process(file: URL) async throws -> TaskResult {
        // Step 1: Extract text and metadata
        guard let extraction = textExtractor.extract(from: file) else {
            // Image-only, corrupt, or password-protected
            AppLogger.shared.warn("No text extractable from PDF",
                context: ["file": file.lastPathComponent])
            return .skipped(reason: "No extractable text (image-only or protected)")
        }
        
        // Step 2: Classify via LM Studio (with retries)
        guard let isPaper = await classifyWithRetry(
            text: extraction.text,
            metadata: extraction.metadata,
            client: client,
            maxRetries: 3
        ) else {
            AppLogger.shared.error("Classification failed after all retries",
                context: ["file": file.lastPathComponent])
            return .skipped(reason: "Classification failed — leaving in Downloads")
        }
        
        // Step 3: Route based on classification
        guard isPaper else {
            return .skipped(reason: "Not classified as a scientific paper")
        }
        
        // Step 4: Move to ~/Documents/Papers
        let destPath = NSString(string: config.destinationPath).expandingTildeInPath
        let destDir = URL(fileURLWithPath: destPath, isDirectory: true)
        
        try FileManager.default.createDirectory(
            at: destDir, withIntermediateDirectories: true
        )
        
        let destination = destDir.appendingPathComponent(file.lastPathComponent)
        
        // Duplicate check: skip if same filename exists
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            return .skipped(reason: "File already exists in Papers")
        }
        
        try FileManager.default.moveItem(at: file, to: destination)
        
        return .processed(action: "Moved to ~/Documents/Papers")
    }
}
```

---

## 8. Sources

| Source | What It Confirms |
|--------|-----------------|
| Apple PDFKit Documentation (developer.apple.com/documentation/pdfkit) | PDFDocument, PDFPage.string, documentAttributes, isLocked API |
| Apple URLSession Documentation (developer.apple.com/documentation/foundation/urlsession) | async/await data(for:) API, URLRequest configuration |
| LM Studio Documentation (lmstudio.ai/docs) | OpenAI-compatible /v1/chat/completions endpoint, /v1/models health endpoint |
| OpenAI Chat Completions API Reference (platform.openai.com/docs/api-reference/chat) | Request/response JSON schema (model, messages, temperature, max_tokens, choices) |
| Existing codebase: AudioFileIdentifier.swift | Dual-gate UTType pattern for file identification |
| Existing codebase: AudioTask.swift | FileTask pipeline pattern (canHandle → process → TaskResult) |
| Existing codebase: FFmpegService.swift | External service integration pattern (Locator + Converter decomposition) |
| Existing codebase: AppCoordinator.swift | Task registration, event routing, service wiring at startup |
| Existing codebase: Phase 3 Plan 03-03 | Menu bar guidance pattern (AppState flag + conditional MenuBarView section) |

---

*Research completed: 2026-02-22*
*Phase: 04-pdf-classification*
