import XCTest
@testable import OhMyClaw

final class FileWatcherTests: XCTestCase {

    // MARK: - URL Extension Tests

    func testHiddenFileDetection() {
        let hidden = URL(fileURLWithPath: "/tmp/.DS_Store")
        let visible = URL(fileURLWithPath: "/tmp/report.pdf")

        XCTAssertTrue(hidden.isHiddenFile)
        XCTAssertFalse(visible.isHiddenFile)
    }

    func testDotfileIsHidden() {
        let dotfile = URL(fileURLWithPath: "/tmp/.localized")
        XCTAssertTrue(dotfile.isHiddenFile)
        XCTAssertTrue(dotfile.shouldBeIgnored)
    }

    func testTemporaryDownloadExtensions() {
        let tempExtensions = ["crdownload", "part", "tmp", "download", "partial", "downloading"]
        for ext in tempExtensions {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            XCTAssertTrue(url.isTemporaryDownload,
                          ".\(ext) should be detected as temporary download")
            XCTAssertTrue(url.shouldBeIgnored,
                          ".\(ext) should be ignored")
        }
    }

    func testNonTemporaryExtensions() {
        let normalExtensions = ["mp3", "pdf", "wav", "flac", "aiff", "jpg", "zip"]
        for ext in normalExtensions {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            XCTAssertFalse(url.isTemporaryDownload,
                           ".\(ext) should NOT be detected as temporary download")
        }
    }

    func testCaseInsensitiveExtensionMatching() {
        let upper = URL(fileURLWithPath: "/tmp/file.CRDOWNLOAD")
        let mixed = URL(fileURLWithPath: "/tmp/file.CrDownload")

        XCTAssertTrue(upper.isTemporaryDownload)
        XCTAssertTrue(mixed.isTemporaryDownload)
    }

    func testShouldBeIgnoredCombinesChecks() {
        // Hidden but not temp
        XCTAssertTrue(URL(fileURLWithPath: "/tmp/.gitignore").shouldBeIgnored)
        // Temp but not hidden
        XCTAssertTrue(URL(fileURLWithPath: "/tmp/file.crdownload").shouldBeIgnored)
        // Neither hidden nor temp
        XCTAssertFalse(URL(fileURLWithPath: "/tmp/song.mp3").shouldBeIgnored)
        // Both hidden and temp (unlikely but should still be ignored)
        XCTAssertTrue(URL(fileURLWithPath: "/tmp/.file.tmp").shouldBeIgnored)
    }

    // MARK: - FileEvent Tests

    func testFileAppearedEvent() {
        let event = FileEvent(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            flags: UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile),
            timestamp: Date()
        )
        XCTAssertTrue(event.isFileAppeared)
        XCTAssertFalse(event.isFileRemoved)
    }

    func testFileRemovedEvent() {
        let event = FileEvent(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            flags: UInt32(kFSEventStreamEventFlagItemRemoved),
            timestamp: Date()
        )
        XCTAssertTrue(event.isFileRemoved)
    }

    func testDirectoryEventNotFileAppeared() {
        let event = FileEvent(
            url: URL(fileURLWithPath: "/tmp/subdir"),
            flags: UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsDir),
            timestamp: Date()
        )
        XCTAssertFalse(event.isFileAppeared, "Directory events should not be treated as file-appeared")
    }

    // MARK: - FileWatcher Initialization Tests

    func testDefaultWatchDirectory() {
        let watcher = FileWatcher()
        // Just verify it initializes without crashing
        XCTAssertNotNil(watcher.events)
    }

    func testCustomWatchDirectory() {
        let customDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyClawTest-\(UUID().uuidString)")
        let watcher = FileWatcher(directory: customDir, debounceSeconds: 1.0)
        XCTAssertNotNil(watcher.events)
    }

    // MARK: - Scan Existing Files Tests

    func testScanExistingFilesSkipsHiddenAndTemp() async throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyClawScanTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        // Create test files
        let visibleFile = testDir.appendingPathComponent("song.mp3")
        let hiddenFile = testDir.appendingPathComponent(".hidden")
        let tempFile = testDir.appendingPathComponent("download.crdownload")
        let pdfFile = testDir.appendingPathComponent("paper.pdf")

        for file in [visibleFile, hiddenFile, tempFile, pdfFile] {
            try "test".write(to: file, atomically: true, encoding: .utf8)
        }

        let watcher = FileWatcher(directory: testDir, debounceSeconds: 0.1)

        var scannedFiles: [URL] = []
        let expectation = XCTestExpectation(description: "scan complete")

        // Collect events from scan
        Task {
            for await url in watcher.events {
                scannedFiles.append(url)
                if scannedFiles.count >= 2 {
                    expectation.fulfill()
                }
            }
        }

        await watcher.scanExistingFiles()

        await fulfillment(of: [expectation], timeout: 5.0)

        let scannedNames = Set(scannedFiles.map { $0.lastPathComponent })
        XCTAssertTrue(scannedNames.contains("song.mp3"), "Should scan visible mp3")
        XCTAssertTrue(scannedNames.contains("paper.pdf"), "Should scan visible pdf")
        XCTAssertFalse(scannedNames.contains(".hidden"), "Should skip hidden files")
        XCTAssertFalse(scannedNames.contains("download.crdownload"), "Should skip temp files")

        watcher.stop()
    }
}
