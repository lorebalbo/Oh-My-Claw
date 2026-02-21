import Foundation

extension URL {
    /// The user's ~/Downloads directory.
    static var downloadsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    /// Whether this URL points to a hidden file (name starts with `.`).
    var isHiddenFile: Bool {
        lastPathComponent.hasPrefix(".")
    }

    /// Whether this file has a temporary/partial download extension.
    /// Checks against the known blocklist of temp extensions.
    var isTemporaryDownload: Bool {
        let tempExtensions: Set<String> = [
            "crdownload", "part", "tmp", "download", "partial", "downloading"
        ]
        return tempExtensions.contains(pathExtension.lowercased())
    }

    /// Whether this URL should be ignored by the file watcher.
    /// Combines hidden file check + temporary extension check.
    var shouldBeIgnored: Bool {
        isHiddenFile || isTemporaryDownload
    }

    /// File size in bytes, or nil if the file doesn't exist or can't be read.
    var fileSize: Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }

    /// Whether the file currently exists on disk.
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Whether this URL is a directory.
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }
}
