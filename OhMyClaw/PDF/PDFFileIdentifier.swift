import Foundation
import UniformTypeIdentifiers

/// Identifies whether a file URL points to a recognized PDF file.
///
/// Uses a dual-gate approach: the file extension must be "pdf"
/// AND the UTType for that extension must conform to `.pdf`.
struct PDFFileIdentifier: Sendable {

    /// Returns `true` only if the file has a `.pdf` extension
    /// AND the system's UTType for that extension conforms to `.pdf`.
    func isRecognizedPDFFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()

        guard ext == "pdf" else {
            return false
        }

        guard let utType = UTType(filenameExtension: ext),
              utType.conforms(to: .pdf) else {
            return false
        }

        return true
    }
}
