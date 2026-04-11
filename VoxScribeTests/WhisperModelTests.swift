import XCTest
@testable import VoxScribe

final class WhisperModelTests: XCTestCase {
    func testAllModelsHaveUniqueNames() {
        let names = WhisperModel.allModels.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testAllModelsCount() {
        XCTAssertEqual(WhisperModel.allModels.count, 9)
    }

    func testEnglishOnlyModelsAreMarked() {
        let englishOnly = WhisperModel.allModels.filter { $0.isEnglishOnly }
        XCTAssertEqual(englishOnly.count, 4)
        for model in englishOnly {
            XCTAssertTrue(model.name.hasSuffix(".en"))
        }
    }

    func testFilenameFormat() {
        let tiny = WhisperModel.allModels.first { $0.name == "tiny" }!
        XCTAssertEqual(tiny.filename, "ggml-tiny.bin")
    }

    func testDownloadURLIsValid() {
        let base = WhisperModel.allModels.first { $0.name == "base" }!
        XCTAssertTrue(base.downloadURL.absoluteString.contains("ggml-base.bin"))
    }

    func testStorageDirectoryPath() {
        let expectedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/VoxScribe Models")
        XCTAssertEqual(WhisperModel.storageDirectory, expectedPath)
    }

    func testModelFilePath() {
        let tiny = WhisperModel.allModels.first { $0.name == "tiny" }!
        let expected = WhisperModel.storageDirectory.appendingPathComponent("ggml-tiny.bin")
        XCTAssertEqual(tiny.localFilePath, expected)
    }
}
