import Foundation

/// Thread-safe in-memory index of existing audio files in ~/Music.
///
/// Keyed by normalized "title|artist" strings (trimmed, lowercased).
/// Used by AudioTask to detect duplicates before moving new files.
/// Built at app launch with bounded concurrent metadata reads (max 8).
actor MusicLibraryIndex {
    private var index: [String: URL] = [:]
    private let identifier: AudioFileIdentifier
    private let metadataReader: AudioMetadataReader

    init(identifier: AudioFileIdentifier = AudioFileIdentifier(),
         metadataReader: AudioMetadataReader = AudioMetadataReader()) {
        self.identifier = identifier
        self.metadataReader = metadataReader
    }

    // MARK: - Key Normalization

    private static func normalizeKey(title: String, artist: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(t)|\(a)"
    }

    // MARK: - Build Index

    /// Recursively enumerates `musicDirectory`, reads metadata from recognized
    /// audio files using a bounded TaskGroup (max 8 concurrent), and populates
    /// the in-memory index.
    func build(from musicDirectory: URL) async {
        let start = CFAbsoluteTimeGetCurrent()

        // Collect all recognized audio file URLs
        var audioURLs: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: musicDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if identifier.isRecognizedAudioFile(fileURL) {
                    audioURLs.append(fileURL)
                }
            }
        }

        // Read metadata with bounded concurrency (max 8 parallel reads)
        let reader = metadataReader

        await withTaskGroup(of: (String, URL)?.self) { group in
            var inFlight = 0
            var urlIterator = audioURLs.makeIterator()

            // Seed up to 8 tasks
            while inFlight < 8, let url = urlIterator.next() {
                group.addTask {
                    guard let metadata = try? await reader.read(from: url),
                          let title = metadata.title,
                          let artist = metadata.artist else {
                        return nil
                    }
                    let key = MusicLibraryIndex.normalizeKey(title: title, artist: artist)
                    return (key, url)
                }
                inFlight += 1
            }

            // As each task finishes, submit the next
            while let result = await group.next() {
                inFlight -= 1
                if let (key, url) = result {
                    index[key] = url
                }
                if let url = urlIterator.next() {
                    group.addTask {
                        guard let metadata = try? await reader.read(from: url),
                              let title = metadata.title,
                              let artist = metadata.artist else {
                            return nil
                        }
                        let key = MusicLibraryIndex.normalizeKey(title: title, artist: artist)
                        return (key, url)
                    }
                    inFlight += 1
                }
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        AppLogger.shared.info("Music library indexed", context: [
            "count": "\(index.count)",
            "elapsed": "\(String(format: "%.1f", elapsed))s"
        ])
    }

    // MARK: - Query

    /// Returns `true` if a file with the same title+artist already exists in the index.
    func contains(title: String, artist: String) -> Bool {
        let key = Self.normalizeKey(title: title, artist: artist)
        return index[key] != nil
    }

    /// Returns the URL of the indexed file matching the given title+artist, if any.
    func url(for title: String, artist: String) -> URL? {
        let key = Self.normalizeKey(title: title, artist: artist)
        return index[key]
    }

    // MARK: - Mutation

    /// Adds or updates the index entry for the given title+artist.
    func add(title: String, artist: String, url: URL) {
        let key = Self.normalizeKey(title: title, artist: artist)
        index[key] = url
    }

    /// Removes the index entry for the given title+artist.
    func remove(title: String, artist: String) {
        let key = Self.normalizeKey(title: title, artist: artist)
        index[key] = nil
    }
}
