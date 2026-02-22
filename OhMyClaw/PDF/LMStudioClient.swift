import Foundation

// MARK: - LMStudioError

/// Errors produced when communicating with the LM Studio API.
enum LMStudioError: Error, Sendable {
    /// LM Studio is not running or refused the connection.
    case unreachable
    /// The server returned a non-200 HTTP status code.
    case badResponse(statusCode: Int)
    /// The response contained no choices or nil content.
    case emptyResponse
    /// JSON decoding failed.
    case decodingFailed(String)
}

// MARK: - API Models

/// Request body for the /v1/chat/completions endpoint.
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

/// Response from the /v1/chat/completions endpoint.
struct ChatCompletionResponse: Decodable, Sendable {
    let choices: [Choice]

    struct Choice: Decodable, Sendable {
        let message: Message
    }

    struct Message: Decodable, Sendable {
        let content: String
    }
}

/// Parsed classification result from the LLM response.
struct ClassificationResult: Decodable, Sendable {
    let is_paper: Bool
}

// MARK: - LMStudioClient

/// HTTP client for the local LM Studio API.
///
/// Provides health checking via GET /v1/models and binary
/// scientific paper classification via POST /v1/chat/completions.
struct LMStudioClient: Sendable {
    let baseURL: URL
    let modelName: String
    let timeout: TimeInterval

    /// Creates a client pointing at a local LM Studio instance.
    ///
    /// - Parameters:
    ///   - port: The port LM Studio is listening on (default 1234).
    ///   - modelName: Model to use for classification. Empty string means
    ///     "use whatever model is currently loaded".
    ///   - timeout: Request timeout in seconds for classification calls.
    init(port: Int, modelName: String, timeout: TimeInterval = 30) {
        self.baseURL = URL(string: "http://localhost:\(port)/v1")!
        self.modelName = modelName
        self.timeout = timeout
    }

    // MARK: - Health Check

    /// Quick check whether LM Studio is reachable.
    ///
    /// Sends GET /v1/models with a 5-second timeout.
    /// Returns `true` if the server responds with HTTP 200.
    func isAvailable() async -> Bool {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Classification

    /// Classifies extracted PDF text as a scientific paper or not.
    ///
    /// Sends the raw page text to the LM Studio chat completions endpoint
    /// and parses the binary result.
    ///
    /// - Parameter text: Extracted PDF text content (first 10 pages).
    /// - Returns: `true` if the document is classified as a scientific paper.
    /// - Throws: `LMStudioError` on connection, response, or parsing failures.
    func classify(text: String) async throws -> Bool {
        let url = baseURL.appendingPathComponent("chat/completions")

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

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LMStudioError.unreachable
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LMStudioError.badResponse(statusCode: statusCode)
        }

        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw LMStudioError.decodingFailed(error.localizedDescription)
        }

        guard let content = decoded.choices.first?.message.content else {
            throw LMStudioError.emptyResponse
        }

        return parseClassification(content)
    }

    // MARK: - Retry Wrapper

    /// Attempts classification with exponential backoff on failure.
    ///
    /// Returns `nil` when all retries are exhausted — the caller should
    /// treat nil as "leave in Downloads".
    ///
    /// - Parameters:
    ///   - text: Extracted PDF text content.
    ///   - client: The LM Studio client to use.
    ///   - maxRetries: Maximum number of retry attempts (default 3, so 4 total).
    /// - Returns: Classification result, or `nil` if all attempts failed.
    static func classifyWithRetry(
        text: String,
        client: LMStudioClient,
        maxRetries: Int = 3
    ) async -> Bool? {
        let backoffSeconds: [UInt64] = [2, 4, 8]

        for attempt in 0...maxRetries {
            do {
                let result = try await client.classify(text: text)
                return result
            } catch {
                AppLogger.shared.warn("Classification attempt failed", context: [
                    "attempt": "\(attempt + 1)/\(maxRetries + 1)",
                    "error": "\(error)"
                ])
                if attempt < maxRetries {
                    let delay = backoffSeconds[min(attempt, backoffSeconds.count - 1)]
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                }
            }
        }

        return nil
    }

    // MARK: - Private

    /// Parses the LLM response into a boolean classification.
    ///
    /// Conservative strategy: only returns `true` when the response
    /// explicitly indicates a paper. Ambiguous or unparseable responses
    /// default to `false` (better to miss a paper than misfile a receipt).
    private func parseClassification(_ response: String) -> Bool {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Try JSON decode first
        if let data = trimmed.data(using: .utf8),
           let result = try? JSONDecoder().decode(ClassificationResult.self, from: data) {
            return result.is_paper
        }

        // Fallback: check for string patterns in JSON format
        if trimmed.contains("\"is_paper\": true") || trimmed.contains("\"is_paper\":true") {
            return true
        }

        // Fallback: check for "Answer: Yes" format
        if trimmed.contains("answer: yes") || trimmed.hasPrefix("yes") {
            return true
        }

        // Conservative default — anything else is not a paper
        return false
    }
}
