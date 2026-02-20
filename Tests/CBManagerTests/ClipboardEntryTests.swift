import XCTest
@testable import CBManager

final class ClipboardEntryTests: XCTestCase {
    func testTextTitleLineCompactsAndTruncates() {
        let longText = Array(repeating: "verylongsegment", count: 20).joined(separator: " ")
        let entry = ClipboardEntry(
            id: "1",
            content: "line1\nline2 \(longText)",
            date: Date(),
            sourceApp: "Xcode",
            kind: .text,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )

        XCTAssertFalse(entry.titleLine.contains("\n"))
        XCTAssertTrue(entry.titleLine.hasSuffix("…"))
    }

    func testImageTitleLineUsesOCRSummary() {
        let entry = ClipboardEntry(
            id: "2",
            content: "",
            date: Date(),
            sourceApp: "Preview",
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "Invoice #9382 due next Friday",
            isOCRPending: false
        )

        XCTAssertEqual(entry.titleLine, "Image · Invoice #9382 due next Friday")
    }

    func testImageTitleLinePendingState() {
        let entry = ClipboardEntry(
            id: "3",
            content: "",
            date: Date(),
            sourceApp: "Preview",
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "",
            isOCRPending: true
        )

        XCTAssertEqual(entry.titleLine, "Image · extracting text…")
    }

    func testSearchHintsIncludeQueryForSQLCode() {
        let entry = ClipboardEntry(
            id: "4",
            content: "SELECT * FROM users WHERE id = 1",
            date: Date(),
            sourceApp: "DBConsole",
            kind: .code,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )

        XCTAssertTrue(entry.searchableText.contains("query"))
        XCTAssertTrue(entry.searchableText.contains("sql"))
    }
}
