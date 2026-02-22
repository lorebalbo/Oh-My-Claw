import XCTest
@testable import OhMyClaw

// MARK: - QualityTierTests

final class QualityTierTests: XCTestCase {

    func testTierOrdering() {
        let ordered: [QualityTier] = [.mp3_128, .aac_256, .mp3_320, .aiff, .alac, .flac, .wav]
        for i in 0..<ordered.count - 1 {
            XCTAssertTrue(ordered[i] < ordered[i + 1],
                          "\(ordered[i]) should be less than \(ordered[i + 1])")
        }
    }

    func testTierRawValues() {
        XCTAssertEqual(QualityTier.mp3_128.rawValue, "mp3_128")
        XCTAssertEqual(QualityTier.aac_256.rawValue, "aac_256")
        XCTAssertEqual(QualityTier.mp3_320.rawValue, "mp3_320")
        XCTAssertEqual(QualityTier.aiff.rawValue, "aiff")
        XCTAssertEqual(QualityTier.alac.rawValue, "alac")
        XCTAssertEqual(QualityTier.flac.rawValue, "flac")
        XCTAssertEqual(QualityTier.wav.rawValue, "wav")
    }

    func testTierComparable() {
        // Inclusive cutoff: at cutoff qualifies
        XCTAssertTrue(QualityTier.mp3_320 >= .mp3_320,
                      "mp3_320 should be >= mp3_320 (inclusive cutoff)")
        XCTAssertTrue(QualityTier.flac >= .mp3_320,
                      "flac should be >= mp3_320")
        XCTAssertFalse(QualityTier.mp3_128 >= .mp3_320,
                       "mp3_128 should not be >= mp3_320")
    }
}

// MARK: - QualityEvaluatorTests

final class QualityEvaluatorTests: XCTestCase {

    func testResolveTierLossless() {
        // Lossless formats bypass bitrate check entirely
        XCTAssertEqual(QualityEvaluator.resolveTier(format: .wav, bitrateKbps: 0), .wav)
        XCTAssertEqual(QualityEvaluator.resolveTier(format: .flac, bitrateKbps: 0), .flac)
        XCTAssertEqual(QualityEvaluator.resolveTier(format: .alac, bitrateKbps: 0), .alac)
        XCTAssertEqual(QualityEvaluator.resolveTier(format: .aiff, bitrateKbps: 0), .aiff)
    }

    func testResolveTierMP3() {
        XCTAssertEqual(QualityEvaluator.resolveTier(format: .mp3, bitrateKbps: 320), .mp3_320)
        XCTAssertEqual(QualityEvaluator.resolveTier(format: .mp3, bitrateKbps: 250), .mp3_128,
                       "250 kbps should round down to mp3_128")
        XCTAssertEqual(QualityEvaluator.resolveTier(format: .mp3, bitrateKbps: 128), .mp3_128)
        XCTAssertNil(QualityEvaluator.resolveTier(format: .mp3, bitrateKbps: 64),
                     "64 kbps MP3 should resolve to nil (below lowest tier)")
    }

    func testResolveTierAAC() {
        XCTAssertEqual(QualityEvaluator.resolveTier(format: .aac, bitrateKbps: 256), .aac_256)
        XCTAssertEqual(QualityEvaluator.resolveTier(format: .aac, bitrateKbps: 320), .aac_256,
                       "AAC 320 should still resolve to aac_256 (highest AAC tier)")
        XCTAssertNil(QualityEvaluator.resolveTier(format: .aac, bitrateKbps: 128),
                     "128 kbps AAC should resolve to nil (below aac_256)")
    }

    func testResolveTierUnknown() {
        XCTAssertNil(QualityEvaluator.resolveTier(format: .unknown(extension: "ogg"), bitrateKbps: 320),
                     "Unknown format should always resolve to nil")
    }

    func testIsHighQualityCutoff() {
        XCTAssertTrue(QualityEvaluator.isHighQuality(tier: .flac, cutoff: .mp3_320),
                      "flac is above mp3_320 cutoff")
        XCTAssertFalse(QualityEvaluator.isHighQuality(tier: .mp3_128, cutoff: .mp3_320),
                       "mp3_128 is below mp3_320 cutoff")
        XCTAssertTrue(QualityEvaluator.isHighQuality(tier: .mp3_320, cutoff: .mp3_320),
                      "mp3_320 at cutoff mp3_320 should be high quality (inclusive)")
        XCTAssertFalse(QualityEvaluator.isHighQuality(tier: nil, cutoff: .mp3_320),
                       "nil tier should not be high quality")
    }
}

// MARK: - AudioFormatTests

final class AudioFormatTests: XCTestCase {

    func testIsLossless() {
        XCTAssertTrue(AudioFormat.wav.isLossless)
        XCTAssertTrue(AudioFormat.flac.isLossless)
        XCTAssertTrue(AudioFormat.alac.isLossless)
        XCTAssertTrue(AudioFormat.aiff.isLossless)

        XCTAssertFalse(AudioFormat.mp3.isLossless)
        XCTAssertFalse(AudioFormat.aac.isLossless)
        XCTAssertFalse(AudioFormat.unknown(extension: "ogg").isLossless)
    }

    func testFromExtension() {
        XCTAssertEqual(AudioFormat.fromExtension("mp3"), .mp3)
        XCTAssertEqual(AudioFormat.fromExtension("m4a"), .aac)
        XCTAssertEqual(AudioFormat.fromExtension("flac"), .flac)
        XCTAssertEqual(AudioFormat.fromExtension("wav"), .wav)
        XCTAssertEqual(AudioFormat.fromExtension("aiff"), .aiff)
        XCTAssertEqual(AudioFormat.fromExtension("aif"), .aiff)
        XCTAssertEqual(AudioFormat.fromExtension("xyz"), .unknown(extension: "xyz"))
    }
}

// MARK: - CSVRowTests

final class CSVRowTests: XCTestCase {

    func testSimpleRow() {
        let row = CSVRow(
            filename: "song.mp3",
            title: "Song Title",
            artist: "Artist Name",
            album: "Album",
            format: "mp3",
            bitrate: "128",
            date: "2026-02-22"
        )
        XCTAssertEqual(row.csvLine, "song.mp3,Song Title,Artist Name,Album,mp3,128,2026-02-22")
    }

    func testEscapingCommas() {
        let row = CSVRow(
            filename: "file.mp3",
            title: "Title, With Comma",
            artist: "Artist",
            album: "Album",
            format: "mp3",
            bitrate: "320",
            date: "2026-02-22"
        )
        XCTAssertTrue(row.csvLine.contains("\"Title, With Comma\""),
                      "Field with comma should be wrapped in double-quotes")
    }

    func testEscapingQuotes() {
        let row = CSVRow(
            filename: "file.mp3",
            title: "Title \"Quoted\"",
            artist: "Artist",
            album: "Album",
            format: "mp3",
            bitrate: "320",
            date: "2026-02-22"
        )
        XCTAssertTrue(row.csvLine.contains("\"Title \"\"Quoted\"\"\""),
                      "Field with quotes should have quotes doubled and be wrapped")
    }

    func testEscapingNewlines() {
        let row = CSVRow(
            filename: "file.mp3",
            title: "Title\nWith Newline",
            artist: "Artist",
            album: "Album",
            format: "mp3",
            bitrate: "320",
            date: "2026-02-22"
        )
        XCTAssertTrue(row.csvLine.contains("\"Title\nWith Newline\""),
                      "Field with newline should be wrapped in double-quotes")
    }
}
