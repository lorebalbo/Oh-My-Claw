import Foundation
import PDFKit

/// Document-level metadata extracted from a PDF's attributes.
struct PDFMetadata: Sendable {
    let title: String?
    let author: String?
    let subject: String?
}

/// Extracts text and metadata from PDF files using PDFKit.
///
/// Extracts the first 10 pages of text for LLM classification.
/// Text is cleaned of artifacts but sent in full to give the LLM
/// maximum context for classification decisions.
///
/// Returns `nil` for password-protected or image-only PDFs.
struct PDFTextExtractor: Sendable {

    /// Maximum number of pages to extract for classification.
    private let maxPages = 10

    /// Extracts text and metadata from the PDF at the given URL.
    ///
    /// - Parameter url: File URL pointing to a PDF document.
    /// - Returns: A tuple of cleaned text and metadata, or `nil` if the PDF
    ///   is unreadable, password-protected, or contains no text layer.
    func extract(from url: URL) -> (text: String, metadata: PDFMetadata)? {
        guard let document = PDFDocument(url: url) else {
            return nil
        }

        guard !document.isLocked else {
            return nil
        }

        // Extract metadata from document attributes
        let attributes = document.documentAttributes ?? [:]
        let metadata = PDFMetadata(
            title: attributes[PDFDocumentAttribute.titleAttribute] as? String,
            author: attributes[PDFDocumentAttribute.authorAttribute] as? String,
            subject: attributes[PDFDocumentAttribute.subjectAttribute] as? String
        )

        // Extract first N pages
        let limit = min(document.pageCount, maxPages)
        var parts: [String] = []
        for i in 0..<limit {
            guard let page = document.page(at: i),
                  let text = page.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            parts.append(text)
        }

        let combined = parts.joined(separator: "\n")
        let cleaned = cleanup(combined)

        // Image-only PDF — no text layer on any page
        guard !cleaned.isEmpty else {
            return nil
        }

        return (text: cleaned, metadata: metadata)
    }

    // MARK: - Private

    /// Collapses whitespace and strips standalone page number patterns.
    private func cleanup(_ text: String) -> String {
        // Collapse multiple whitespace/newlines into single spaces
        var cleaned = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        // Strip standalone page number patterns
        cleaned = cleaned.replacingOccurrences(
            of: "\\b\\d{1,4}\\b(?=\\s|$)",
            with: "",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
