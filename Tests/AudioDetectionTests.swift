import XCTest
@testable import OhMyClaw

// MARK: - AudioFileIdentifierTests

final class AudioFileIdentifierTests: XCTestCase {
    private let identifier = AudioFileIdentifier()

    func testRecognizesMP3() {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        XCTAssertTrue(identifier.isRecognizedAudioFile(url))
    }

    func testRecognizesM4A() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        XCTAssertTrue(identifier.isRecognizedAudioFile(url))
    }

    func testRecognizesFLAC() {
        let url = URL(fileURLWithPath: "/tmp/test.flac")
        XCTAssertTrue(identifier.isRecognizedAudioFile(url))
    }

    func testRecognizesWAV() {
        let url = URL(fileURLWithPath: "/tmp/test.wav")
        XCTAssertTrue(identifier.isRecognizedAudioFile(url))
    }

    func testRecognizesAIFF() {
        let aiff = URL(fileURLWithPath: "/tmp/test.aiff")
        let aif = URL(fileURLWithPath: "/tmp/test.aif")
        XCTAssertTrue(identifier.isRecognizedAudioFile(aiff),
                      ".aiff should be recognized as audio")
        XCTAssertTrue(identifier.isRecognizedAudioFile(aif),
                      ".aif should be recognized as audio")
    }

    func testRejectsNonAudioExtension() {
        let extensions = ["pdf", "jpg", "txt", "zip"]
        for ext in extensions {
            let url = URL(fileURLWithPath: "/tmp/test.\(ext)")
            XCTAssertFalse(identifier.isRecognizedAudioFile(url),
                           ".\(ext) should not be recognized as audio")
        }
    }

    func testRejectsNoExtension() {
        let url = URL(fileURLWithPath: "/tmp/testfile")
        XCTAssertFalse(identifier.isRecognizedAudioFile(url),
                       "File without extension should not be recognized as audio")
    }

    func testRejectsTempExtensions() {
        let extensions = ["crdownload", "tmp"]
        for ext in extensions {
            let url = URL(fileURLWithPath: "/tmp/test.\(ext)")
            XCTAssertFalse(identifier.isRecognizedAudioFile(url),
                           ".\(ext) should not be recognized as audio")
        }
    }

    func testCaseInsensitive() {
        let mp3Upper = URL(fileURLWithPath: "/tmp/test.MP3")
        let flacMixed = URL(fileURLWithPath: "/tmp/test.Flac")
        XCTAssertTrue(identifier.isRecognizedAudioFile(mp3Upper),
                      ".MP3 should be recognized (case insensitive)")
        XCTAssertTrue(identifier.isRecognizedAudioFile(flacMixed),
                      ".Flac should be recognized (case insensitive)")
    }
}

// MARK: - AudioMetadataTests

final class AudioMetadataTests: XCTestCase {

    func testHasRequiredFieldsAllPresent() {
        let metadata = AudioMetadata(
            title: "Song",
            artist: "Artist",
            album: "Album",
            durationSeconds: 180.0,
            format: .mp3,
            bitrateKbps: 320
        )
        XCTAssertTrue(metadata.hasRequiredFields(["title", "artist", "album"]))
    }

    func testHasRequiredFieldsMissingTitle() {
        let metadata = AudioMetadata(
            title: nil,
            artist: "Artist",
            album: "Album",
            durationSeconds: 180.0,
            format: .mp3,
            bitrateKbps: 320
        )
        XCTAssertFalse(metadata.hasRequiredFields(["title", "artist", "album"]))
    }

    func testHasRequiredFieldsSubset() {
        let metadata = AudioMetadata(
            title: "Song",
            artist: nil,
            album: nil,
            durationSeconds: 180.0,
            format: .mp3,
            bitrateKbps: 320
        )
        XCTAssertTrue(metadata.hasRequiredFields(["title"]))
    }

    func testHasRequiredFieldsEmptyList() {
        let metadata = AudioMetadata(
            title: nil,
            artist: nil,
            album: nil,
            durationSeconds: 0.0,
            format: .unknown(extension: "ogg"),
            bitrateKbps: 0
        )
        XCTAssertTrue(metadata.hasRequiredFields([]),
                      "Empty required fields list should always return true")
    }

    func testMissingFieldsReturnsCorrectNames() {
        let metadata = AudioMetadata(
            title: "Song",
            artist: nil,
            album: "Album",
            durationSeconds: 180.0,
            format: .flac,
            bitrateKbps: 0
        )
        let missing = metadata.missingFields(["title", "artist", "album"])
        XCTAssertEqual(missing, ["artist"])
    }
}

// MARK: - MusicLibraryIndexTests

final class MusicLibraryIndexTests: XCTestCase {

    func testAddAndContains() async {
        let index = MusicLibraryIndex()
        let url = URL(fileURLWithPath: "/tmp/song.mp3")
        await index.add(title: "Song", artist: "Artist", url: url)
        let result = await index.contains(title: "Song", artist: "Artist")
        XCTAssertTrue(result)
    }

    func testContainsReturnsFalseForMissing() async {
        let index = MusicLibraryIndex()
        let result = await index.contains(title: "Nonexistent", artist: "Nobody")
        XCTAssertFalse(result)
    }

    func testNormalizationTrimsAndLowercases() async {
        let index = MusicLibraryIndex()
        let url = URL(fileURLWithPath: "/tmp/song.mp3")
        await index.add(title: "  Title  ", artist: "  ARTIST  ", url: url)
        let result = await index.contains(title: "title", artist: "artist")
        XCTAssertTrue(result,
                      "Index lookup should normalize by trimming and lowercasing")
    }

    func testRemove() async {
        let index = MusicLibraryIndex()
        let url = URL(fileURLWithPath: "/tmp/song.mp3")
        await index.add(title: "Song", artist: "Artist", url: url)
        await index.remove(title: "Song", artist: "Artist")
        let result = await index.contains(title: "Song", artist: "Artist")
        XCTAssertFalse(result,
                       "Entry should not be found after removal")
    }

    func testDifferentKeysDontCollide() async {
        let index = MusicLibraryIndex()
        let url = URL(fileURLWithPath: "/tmp/songA.mp3")
        await index.add(title: "songA", artist: "artistA", url: url)

        let resultDifferentTitle = await index.contains(title: "songB", artist: "artistA")
        XCTAssertFalse(resultDifferentTitle,
                       "Different title with same artist should not match")

        let resultDifferentArtist = await index.contains(title: "songA", artist: "artistB")
        XCTAssertFalse(resultDifferentArtist,
                       "Same title with different artist should not match")
    }
}
