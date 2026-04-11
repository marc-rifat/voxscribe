import XCTest
@testable import VoxScribe

final class ClipboardHistoryTests: XCTestCase {
    private var history: ClipboardHistory!
    private var tempFileURL: URL!

    override func setUp() {
        super.setUp()
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_history_\(UUID().uuidString).json")
        history = ClipboardHistory(fileURL: tempFileURL, limit: 5)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }

    func testAddEntryAppendsToFront() {
        history.addEntry(text: "First")
        history.addEntry(text: "Second")
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.entries[0].text, "Second")
        XCTAssertEqual(history.entries[1].text, "First")
    }

    func testAddEntryPrunesWhenOverLimit() {
        for i in 1...7 {
            history.addEntry(text: "Entry \(i)")
        }
        XCTAssertEqual(history.entries.count, 5)
        XCTAssertEqual(history.entries[0].text, "Entry 7")
        XCTAssertEqual(history.entries[4].text, "Entry 3")
    }

    func testPersistenceRoundTrip() {
        history.addEntry(text: "Persisted entry")
        let loaded = ClipboardHistory(fileURL: tempFileURL, limit: 5)
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries[0].text, "Persisted entry")
    }

    func testClearRemovesAllEntries() {
        history.addEntry(text: "Entry 1")
        history.addEntry(text: "Entry 2")
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testClearDeletesFile() {
        history.addEntry(text: "Entry")
        history.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
    }

    func testUpdateLimitPrunesExcess() {
        for i in 1...5 {
            history.addEntry(text: "Entry \(i)")
        }
        history.updateLimit(3)
        XCTAssertEqual(history.entries.count, 3)
        XCTAssertEqual(history.entries[0].text, "Entry 5")
    }

    func testLoadFromEmptyFileReturnsEmptyEntries() {
        let fresh = ClipboardHistory(fileURL: tempFileURL, limit: 10)
        XCTAssertTrue(fresh.entries.isEmpty)
    }
}
