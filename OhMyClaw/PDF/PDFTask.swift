import Foundation

/// Full PDF classification pipeline conforming to FileTask.
///
/// Pipeline steps:
/// 1. Extract text and metadata via PDFTextExtractor
/// 2. Classify via OpenAI API with retry/backoff
/// 3. Move classified papers to ~/Documents/Papers
///
/// Non-papers, failures, and image-only PDFs are left in ~/Downloads.
struct PDFTask: FileTask, Sendable {
    let id = "pdf"
    let displayName = "PDF Classification"
    let isEnabled: Bool

    private let identifier: PDFFileIdentifier
    private let textExtractor: PDFTextExtractor
    private let client: OpenAIClient
    private let destinationPath: String

    init(identifier: PDFFileIdentifier,
         textExtractor: PDFTextExtractor,
         client: OpenAIClient,
         destinationPath: String,
         isEnabled: Bool) {
        self.identifier = identifier
        self.textExtractor = textExtractor
        self.client = client
        self.destinationPath = destinationPath
        self.isEnabled = isEnabled
    }

    // MARK: - FileTask

    func canHandle(file: URL) -> Bool {
        identifier.isRecognizedPDFFile(file)
    }

    /// Minimum number of pages for a document to be considered a potential
    /// scientific paper. Single-page PDFs (receipts, flyers, etc.) are
    /// short-circuited without calling the LLM.
    private static let minimumPaperPages = 2

    func process(file: URL) async throws -> TaskResult {
        // Step 1: Extract text and metadata
        guard let extraction = textExtractor.extract(from: file) else {
            AppLogger.shared.warn("No text extractable from PDF", context: [
                "file": file.lastPathComponent
            ])
            return .skipped(reason: "No extractable text (image-only or password-protected)")
        }

        // Step 1.5: Short-circuit single-page (or very short) PDFs
        if extraction.pageCount < Self.minimumPaperPages {
            AppLogger.shared.info("PDF too short to be a paper", context: [
                "file": file.lastPathComponent,
                "pages": "\(extraction.pageCount)"
            ])
            return .skipped(reason: "Only \(extraction.pageCount) page(s) — not a paper")
        }

        // Step 2: Classify via OpenAI with retries
        guard let isPaper = await OpenAIClient.classifyWithRetry(
            text: extraction.text,
            client: client,
            maxRetries: 3
        ) else {
            AppLogger.shared.error("Classification failed after all retries", context: [
                "file": file.lastPathComponent
            ])
            return .error(description: "Classification failed after all retries — leaving in Downloads")
        }

        // Step 3: Check classification result
        guard isPaper else {
            return .skipped(reason: "Not classified as a scientific paper")
        }

        // Step 4: Move to ~/Documents/Papers
        let expandedPath = NSString(string: destinationPath).expandingTildeInPath
        let destDir = URL(fileURLWithPath: expandedPath, isDirectory: true)

        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destination = destDir.appendingPathComponent(file.lastPathComponent)

        // Duplicate check — delete from Downloads if already in Papers
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: file)
            return .processed(action: "Duplicate deleted from Downloads — already in Papers")
        }

        try FileManager.default.moveItem(at: file, to: destination)

        AppLogger.shared.info("Paper moved to ~/Documents/Papers", context: [
            "file": file.lastPathComponent
        ])

        return .processed(action: "Classified as paper, moved to ~/Documents/Papers")
    }
}
