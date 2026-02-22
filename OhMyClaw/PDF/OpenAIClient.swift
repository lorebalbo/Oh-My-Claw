import Foundation

// MARK: - OpenAIError

/// Errors produced when communicating with the OpenAI API.
enum OpenAIError: Error, Sendable {
    /// The API key is not configured (empty string).
    case missingApiKey
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

// MARK: - OpenAIClient

/// HTTP client for the OpenAI API.
///
/// Provides binary scientific paper classification via
/// POST to https://api.openai.com/v1/chat/completions
/// with Bearer token authentication.
struct OpenAIClient: Sendable {
    let apiKey: String
    let modelName: String
    let timeout: TimeInterval

    private static let baseURL = URL(string: "https://api.openai.com/v1")!

    /// Creates a client for the OpenAI API.
    ///
    /// - Parameters:
    ///   - apiKey: The OpenAI API key for authentication.
    ///   - modelName: Model to use for classification (e.g. "gpt-4o").
    ///   - timeout: Request timeout in seconds for classification calls.
    init(apiKey: String, modelName: String, timeout: TimeInterval = 60) {
        self.apiKey = apiKey
        self.modelName = modelName
        self.timeout = timeout
    }

    // MARK: - Classification

    /// Classifies extracted PDF text as a scientific paper or not.
    ///
    /// Sends the full page text to the OpenAI chat completions endpoint
    /// with Bearer token authentication and parses the binary result.
    ///
    /// - Parameter text: Extracted PDF text content.
    /// - Returns: `true` if the document is classified as a scientific paper.
    /// - Throws: `OpenAIError` on connection, response, or parsing failures.
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

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenAIError.badResponse(statusCode: -1)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodySnippet = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
            AppLogger.shared.debug("OpenAI error response", context: [
                "statusCode": "\(statusCode)",
                "body": bodySnippet
            ])
            throw OpenAIError.badResponse(statusCode: statusCode)
        }

        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw OpenAIError.decodingFailed(error.localizedDescription)
        }

        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIError.emptyResponse
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
    ///   - client: The OpenAI client to use.
    ///   - maxRetries: Maximum number of retry attempts (default 3, so 4 total).
    /// - Returns: Classification result, or `nil` if all attempts failed.
    static func classifyWithRetry(
        text: String,
        client: OpenAIClient,
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

        // Conservative default — anything else is not a paper
        return false
    }
}
