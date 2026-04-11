import XCTest
@testable import VoxScribe

final class ModelManagerTests: XCTestCase {
    private var manager: ModelManager!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxscribe_test_models_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        manager = ModelManager(storageDirectory: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testDownloadedModelsInitiallyEmpty() {
        XCTAssertTrue(manager.downloadedModels().isEmpty)
    }

    func testDeleteModelRemovesFile() throws {
        let fakePath = tempDirectory.appendingPathComponent("ggml-tiny.bin")
        try Data("fake".utf8).write(to: fakePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakePath.path))

        let model = WhisperModel.allModels.first { $0.name == "tiny" }!
        try manager.deleteModel(model)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fakePath.path))
    }

    func testDeleteNonexistentModelThrows() {
        let model = WhisperModel.allModels.first { $0.name == "large-v3" }!
        XCTAssertThrowsError(try manager.deleteModel(model))
    }

    func testDownloadedModelsListsExistingFiles() throws {
        let fakePath = tempDirectory.appendingPathComponent("ggml-base.bin")
        try Data("fake".utf8).write(to: fakePath)
        let downloaded = manager.downloadedModels()
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded[0].name, "base")
    }

    func testSmallestDownloadedModel() throws {
        let tinyPath = tempDirectory.appendingPathComponent("ggml-tiny.bin")
        let basePath = tempDirectory.appendingPathComponent("ggml-base.bin")
        try Data("fake".utf8).write(to: tinyPath)
        try Data("fake".utf8).write(to: basePath)
        let smallest = manager.smallestDownloadedModel()
        XCTAssertEqual(smallest?.name, "tiny")
    }

    func testSmallestDownloadedModelNilWhenEmpty() {
        XCTAssertNil(manager.smallestDownloadedModel())
    }
}
