import Foundation

/// A single row of data for the low-quality file CSV log.
struct CSVRow: Sendable {
    let filename: String
    let title: String
    let artist: String
    let album: String
    let format: String
    let bitrate: String
    let date: String

    /// Formats all fields as a single RFC 4180 CSV line.
    var csvLine: String {
        [filename, title, artist, album, format, bitrate, date]
            .map { escapeCSV($0) }
            .joined(separator: ",")
    }

    /// Escapes a value per RFC 4180: if it contains comma, double-quote, or newline,
    /// wrap in double-quotes and double any internal quotes.
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

/// Appends CSV rows to a log file, creating headers on first write.
struct CSVWriter: Sendable {
    let fileURL: URL

    private static let headers = "Filename,Title,Artist,Album,Format,Bitrate,Date"

    /// Appends a row to the CSV file, creating the file with headers if it doesn't exist.
    func append(row: CSVRow) throws {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()

        if !fm.fileExists(atPath: fileURL.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try (Self.headers + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        guard let data = (row.csvLine + "\n").data(using: .utf8) else { return }
        handle.write(data)
    }
}
