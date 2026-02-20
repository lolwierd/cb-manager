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

    func testImageTitleLineShowsSourceNotOCR() {
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

        // OCR text no longer appears in titleLine — shows source app instead
        XCTAssertEqual(entry.titleLine, "Image · Preview")
    }

    func testImageTitleLineOCRPendingShowsSource() {
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

        // OCR pending state doesn't affect titleLine — shows image summary
        XCTAssertEqual(entry.titleLine, "Image · Preview")
    }

    // MARK: - AI Title tests

    func testImageTitleLinePrefersAITitle() {
        let entry = ClipboardEntry(
            id: "ai-1",
            content: "",
            date: Date(),
            sourceApp: "Preview",
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "some ocr text",
            isOCRPending: false,
            aiTitle: "A cat sitting on a laptop keyboard",
            isAITitlePending: false
        )

        XCTAssertEqual(entry.titleLine, "A cat sitting on a laptop keyboard")
    }

    func testImageTitleLineFallsBackToSummaryWhenNoAITitle() {
        let entry = ClipboardEntry(
            id: "ai-2",
            content: "",
            date: Date(),
            sourceApp: "Preview",
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "Invoice #1234",
            isOCRPending: false,
            aiTitle: "",
            isAITitlePending: false
        )

        // No AI title → image summary with source (OCR not used in title)
        XCTAssertEqual(entry.titleLine, "Image · Preview")
    }

    func testImageTitleLineShowsSummaryWhileAITitlePending() {
        let entry = ClipboardEntry(
            id: "ai-3",
            content: "",
            date: Date(),
            sourceApp: "Preview",
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "",
            isOCRPending: false,
            aiTitle: "",
            isAITitlePending: true
        )

        // While generating, show the same summary as when AI is off
        XCTAssertEqual(entry.titleLine, "Image · Preview")
    }

    func testImageTitleLineAITitlePendingShowsSummary() {
        let entry = ClipboardEntry(
            id: "ai-4",
            content: "",
            date: Date(),
            sourceApp: "Preview",
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "OCR result here",
            isOCRPending: false,
            aiTitle: "",
            isAITitlePending: true
        )

        XCTAssertEqual(entry.titleLine, "Image · Preview")
    }

    func testSearchableTextIncludesAITitle() {
        let entry = ClipboardEntry(
            id: "ai-5",
            content: "",
            date: Date(),
            sourceApp: "Preview",
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "",
            isOCRPending: false,
            aiTitle: "Screenshot of Xcode IDE",
            isAITitlePending: false
        )

        XCTAssertTrue(entry.searchableText.contains("screenshot of xcode ide"))
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
