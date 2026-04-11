import XCTest
@testable import VoxScribe

final class HistoryEntryTests: XCTestCase {
    func testPreviewTruncatesLongText() {
        let entry = HistoryEntry(
            text: String(repeating: "a", count: 100),
            timestamp: Date()
        )
        XCTAssertEqual(entry.preview.count, 53)
        XCTAssertTrue(entry.preview.hasSuffix("..."))
    }

    func testPreviewKeepsShortText() {
        let entry = HistoryEntry(text: "Short text", timestamp: Date())
        XCTAssertEqual(entry.preview, "Short text")
    }

    func testCodableRoundTrip() throws {
        let entry = HistoryEntry(text: "Hello world", timestamp: Date(timeIntervalSince1970: 1000))
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)
        XCTAssertEqual(decoded.text, entry.text)
        XCTAssertEqual(decoded.timestamp, entry.timestamp)
    }

    func testRelativeTimestampJustNow() {
        let entry = HistoryEntry(text: "test", timestamp: Date())
        XCTAssertEqual(entry.relativeTimestamp, "just now")
    }

    func testRelativeTimestampMinutesAgo() {
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let entry = HistoryEntry(text: "test", timestamp: fiveMinutesAgo)
        XCTAssertEqual(entry.relativeTimestamp, "5 min ago")
    }
}
