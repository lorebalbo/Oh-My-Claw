import XCTest
@testable import OhMyClaw

final class ConfigStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OhMyClawTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func configURL() -> URL {
        tempDir.appendingPathComponent("config.json")
    }

    // MARK: - First Launch

    @MainActor
    func testFirstLaunchCreatesConfigFile() {
        let store = ConfigStore(configURL: configURL())
        store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL().path),
                      "Config file should be created on first launch")
    }

    @MainActor
    func testFirstLaunchUsesDefaults() {
        let store = ConfigStore(configURL: configURL())
        store.load()

        XCTAssertEqual(store.config, AppConfig.defaults,
                       "First launch should use hardcoded defaults")
    }

    // MARK: - Valid Config

    @MainActor
    func testLoadsValidConfig() throws {
        let customConfig = AppConfig(
            watcher: WatcherConfig(
                debounceSeconds: 5.0,
                stabilityCheckInterval: 1.0,
                ignoredExtensions: [".crdownload"]
            ),
            audio: .defaults,
            pdf: .defaults,
            logging: .defaults
        )
        let data = try JSONEncoder().encode(customConfig)
        try data.write(to: configURL())

        let store = ConfigStore(configURL: configURL())
        store.load()

        XCTAssertEqual(store.config.watcher.debounceSeconds, 5.0)
        XCTAssertEqual(store.config.watcher.stabilityCheckInterval, 1.0)
        XCTAssertTrue(store.validationErrors.isEmpty)
    }

    // MARK: - Missing Sections Fallback

    @MainActor
    func testMissingSectionsFallbackToDefaults() throws {
        // JSON with only watcher section — audio, pdf, logging should fall back
        let partialJSON = """
        {
            "watcher": {
                "debounceSeconds": 4.0,
                "stabilityCheckInterval": 0.5,
                "ignoredExtensions": [".crdownload"]
            }
        }
        """.data(using: .utf8)!
        try partialJSON.write(to: configURL())

        let store = ConfigStore(configURL: configURL())
        store.load()

        XCTAssertEqual(store.config.watcher.debounceSeconds, 4.0,
                       "Provided watcher section should be used")
        XCTAssertEqual(store.config.audio, AudioConfig.defaults,
                       "Missing audio section should fall back to defaults")
        XCTAssertEqual(store.config.pdf, PDFConfig.defaults,
                       "Missing pdf section should fall back to defaults")
        XCTAssertEqual(store.config.logging, LoggingConfig.defaults,
                       "Missing logging section should fall back to defaults")
    }

    // MARK: - Invalid Config

    @MainActor
    func testInvalidJSONFallsBackToDefaults() throws {
        try "{ this is not valid json".data(using: .utf8)!.write(to: configURL())

        let store = ConfigStore(configURL: configURL())
        store.load()

        XCTAssertEqual(store.config, AppConfig.defaults,
                       "Invalid JSON should fall back to defaults")
        XCTAssertFalse(store.validationErrors.isEmpty,
                       "Should report validation errors for invalid JSON")
    }

    @MainActor
    func testInvalidValuesReportErrors() throws {
        // Config with out-of-range values
        let badConfig = """
        {
            "watcher": {
                "debounceSeconds": 0.1,
                "stabilityCheckInterval": 0.5,
                "ignoredExtensions": []
            },
            "audio": {
                "enabled": true,
                "requiredMetadataFields": ["title"],
                "minDurationSeconds": -5,
                "qualityCutoff": "mp3_320",
                "destinationPath": "~/Music"
            },
            "pdf": {
                "enabled": true,
                "lmStudioPort": 99999,
                "destinationPath": "~/Documents/Papers"
            },
            "logging": {
                "level": "verbose",
                "maxFileSizeMB": 10,
                "maxRotatedFiles": 3
            }
        }
        """.data(using: .utf8)!
        try badConfig.write(to: configURL())

        let store = ConfigStore(configURL: configURL())
        store.load()

        XCTAssertEqual(store.config, AppConfig.defaults,
                       "Invalid values should fall back to defaults")
        XCTAssertTrue(store.validationErrors.count >= 3,
                      "Should report errors for debounce, minDuration, port, and level")
    }

    // MARK: - Save

    @MainActor
    func testSavePersistsConfig() throws {
        let store = ConfigStore(configURL: configURL())
        var modified = AppConfig.defaults
        modified.watcher.debounceSeconds = 5.0
        store.save(modified)

        // Reload from disk
        let store2 = ConfigStore(configURL: configURL())
        store2.load()
        XCTAssertEqual(store2.config.watcher.debounceSeconds, 5.0)
    }

    @MainActor
    func testSaveWritesAtomically() throws {
        let store = ConfigStore(configURL: configURL())
        store.save(AppConfig.defaults)

        let data = try Data(contentsOf: configURL())
        XCTAssertNoThrow(try JSONDecoder().decode(AppConfig.self, from: data),
                         "Saved file should be valid JSON decodable to AppConfig")
    }

    // MARK: - Defaults Correctness

    func testDefaultValues() {
        let defaults = AppConfig.defaults
        XCTAssertEqual(defaults.watcher.debounceSeconds, 3.0)
        XCTAssertEqual(defaults.watcher.stabilityCheckInterval, 0.5)
        XCTAssertEqual(defaults.watcher.ignoredExtensions.count, 6)
        XCTAssertTrue(defaults.watcher.ignoredExtensions.contains(".crdownload"))
        XCTAssertTrue(defaults.watcher.ignoredExtensions.contains(".part"))
        XCTAssertTrue(defaults.watcher.ignoredExtensions.contains(".tmp"))
        XCTAssertTrue(defaults.watcher.ignoredExtensions.contains(".download"))
        XCTAssertTrue(defaults.watcher.ignoredExtensions.contains(".partial"))
        XCTAssertTrue(defaults.watcher.ignoredExtensions.contains(".downloading"))
        XCTAssertEqual(defaults.audio.minDurationSeconds, 60)
        XCTAssertEqual(defaults.logging.level, "info")
        XCTAssertEqual(defaults.logging.maxFileSizeMB, 10)
        XCTAssertEqual(defaults.logging.maxRotatedFiles, 3)
    }
}
