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
/// Uses an abstract-first strategy: scans for academic abstract sections
/// using multilingual keyword markers. Falls back to the first few pages
/// when no abstract is detected. Text is cleaned and capped at a word limit
/// suitable for LLM classification prompts.
///
/// Returns `nil` for password-protected or image-only PDFs.
struct PDFTextExtractor: Sendable {

    /// Maximum number of words to return in extracted text.
    private let maxWords = 1500

    /// Number of pages to extract when abstract detection fails.
    private let fallbackPageCount = 3

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

        // Try abstract detection on the first page
        let firstPageText = document.page(at: 0)?.string ?? ""
        if let abstract = extractAbstract(from: firstPageText) {
            let cleaned = cleanup(abstract)
            let capped = capWords(cleaned, max: maxWords)
            if !capped.isEmpty {
                return (text: capped, metadata: metadata)
            }
        }

        // Fallback: extract first N pages
        let limit = min(document.pageCount, fallbackPageCount)
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
        let capped = capWords(cleaned, max: maxWords)

        // Image-only PDF — no text layer on any page
        guard !capped.isEmpty else {
            return nil
        }

        return (text: capped, metadata: metadata)
    }

    // MARK: - Private

    /// Attempts to locate and extract an abstract section from text.
    ///
    /// Scans lines for multilingual abstract header markers and collects text
    /// until a section-end marker (e.g., "Introduction", "Keywords") or a
    /// maximum of 30 lines is reached.
    ///
    /// - Returns: The abstract text, or `nil` if no abstract was found or
    ///   the detected section is too short (< 50 characters).
    private func extractAbstract(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)

        let startMarkers = ["abstract", "summary", "résumé", "zusammenfassung", "riassunto"]
        let endMarkers = ["introduction", "1.", "1 ", "keywords", "key words", "i.", "i ", "background"]

        var abstractLines: [String] = []
        var capturing = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else {
                if capturing { abstractLines.append("") }
                continue
            }

            if !capturing {
                if startMarkers.contains(where: { trimmed.hasPrefix($0) }) {
                    capturing = true
                    // Include content after the marker on the same line
                    let remainder = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    let markerEnd = startMarkers.first(where: { trimmed.hasPrefix($0) })!
                    let afterMarker = String(remainder.dropFirst(markerEnd.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !afterMarker.isEmpty {
                        abstractLines.append(afterMarker)
                    }
                }
            } else {
                if endMarkers.contains(where: { trimmed.hasPrefix($0) }) {
                    break
                }
                abstractLines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))

                if abstractLines.count >= 30 {
                    break
                }
            }
        }

        let result = abstractLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.count >= 50 else {
            return nil
        }

        return result
    }

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

    /// Caps text at the given maximum word count.
    private func capWords(_ text: String, max: Int) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)

        guard words.count > max else {
            return text
        }

        return words.prefix(max).joined(separator: " ")
    }
}
