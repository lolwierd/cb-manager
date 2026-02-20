import XCTest
@testable import CBManager

final class ClipboardEntryExtendedTests: XCTestCase {
    // MARK: - titleLine

    func testTitleLineForShortText() {
        let entry = makeEntry(content: "Short text", kind: .text)
        XCTAssertEqual(entry.titleLine, "Short text")
    }

    func testTitleLineForEmptyText() {
        let entry = makeEntry(content: "", kind: .text)
        XCTAssertEqual(entry.titleLine, "")
    }

    func testTitleLineCollapsesNewlinesToSpaces() {
        let entry = makeEntry(content: "line1\nline2\nline3", kind: .text)
        XCTAssertFalse(entry.titleLine.contains("\n"))
        XCTAssertTrue(entry.titleLine.contains("line1 line2 line3"))
    }

    func testTitleLineTruncatesAt96Chars() {
        let long = String(repeating: "a", count: 200)
        let entry = makeEntry(content: long, kind: .text)
        XCTAssertTrue(entry.titleLine.hasSuffix("…"))
        // 96 chars + "…"
        XCTAssertEqual(entry.titleLine.count, 97)
    }

    func testTitleLineForImageWithNoOCRNotPending() {
        let entry = makeEntry(content: "", kind: .image, imagePath: "/tmp/x.png", ocrText: "", isOCRPending: false)
        XCTAssertEqual(entry.titleLine, "Image")
    }

    func testTitleLineForImageWithOCRText() {
        let entry = makeEntry(content: "", kind: .image, imagePath: "/tmp/x.png", ocrText: "Hello World", isOCRPending: false)
        XCTAssertEqual(entry.titleLine, "Image · Hello World")
    }

    func testTitleLineForImageWithLongOCRTruncates() {
        let longOCR = String(repeating: "x", count: 200)
        let entry = makeEntry(content: "", kind: .image, imagePath: "/tmp/x.png", ocrText: longOCR, isOCRPending: false)
        XCTAssertTrue(entry.titleLine.hasPrefix("Image · "))
        XCTAssertTrue(entry.titleLine.hasSuffix("…"))
    }

    func testTitleLineForImagePending() {
        let entry = makeEntry(content: "", kind: .image, imagePath: "/tmp/x.png", ocrText: "", isOCRPending: true)
        XCTAssertEqual(entry.titleLine, "Image · extracting text…")
    }

    func testTitleLineForImageWithOCRAndPending() {
        // If OCR text exists, it should use it even if pending (edge case)
        let entry = makeEntry(content: "", kind: .image, imagePath: "/tmp/x.png", ocrText: "detected", isOCRPending: true)
        XCTAssertEqual(entry.titleLine, "Image · detected")
    }

    func testTitleLineForCodeKind() {
        let entry = makeEntry(content: "func hello() {}", kind: .code)
        XCTAssertEqual(entry.titleLine, "func hello() {}")
    }

    func testTitleLineForLinkKind() {
        let entry = makeEntry(content: "https://example.com", kind: .link)
        XCTAssertEqual(entry.titleLine, "https://example.com")
    }

    func testTitleLineForPathKind() {
        let entry = makeEntry(content: "/usr/local/bin", kind: .path)
        XCTAssertEqual(entry.titleLine, "/usr/local/bin")
    }

    // MARK: - searchHints

    func testSearchHintsForText() {
        let entry = makeEntry(content: "hello", kind: .text)
        XCTAssertTrue(entry.searchHints.contains("text"))
        XCTAssertTrue(entry.searchHints.contains("note"))
        XCTAssertTrue(entry.searchHints.contains("plain"))
    }

    func testSearchHintsForLink() {
        let entry = makeEntry(content: "https://example.com", kind: .link)
        XCTAssertTrue(entry.searchHints.contains("link"))
        XCTAssertTrue(entry.searchHints.contains("url"))
        XCTAssertTrue(entry.searchHints.contains("web"))
        XCTAssertTrue(entry.searchHints.contains("website"))
    }

    func testSearchHintsForPath() {
        let entry = makeEntry(content: "/usr/local/bin", kind: .path)
        XCTAssertTrue(entry.searchHints.contains("path"))
        XCTAssertTrue(entry.searchHints.contains("file"))
        XCTAssertTrue(entry.searchHints.contains("directory"))
        XCTAssertTrue(entry.searchHints.contains("folder"))
    }

    func testSearchHintsForImage() {
        let entry = makeEntry(content: "", kind: .image, imagePath: "/tmp/x.png")
        XCTAssertTrue(entry.searchHints.contains("image"))
        XCTAssertTrue(entry.searchHints.contains("photo"))
        XCTAssertTrue(entry.searchHints.contains("screenshot"))
        XCTAssertTrue(entry.searchHints.contains("picture"))
    }

    func testSearchHintsForCodeWithoutSQL() {
        let entry = makeEntry(content: "func hello() {}", kind: .code)
        XCTAssertTrue(entry.searchHints.contains("code"))
        XCTAssertTrue(entry.searchHints.contains("snippet"))
        XCTAssertTrue(entry.searchHints.contains("command"))
        XCTAssertTrue(entry.searchHints.contains("query"))
        // Should not contain SQL hints
        XCTAssertFalse(entry.searchHints.contains("sql"))
    }

    func testSearchHintsForCodeWithSQL() {
        let entry = makeEntry(content: "SELECT * FROM users", kind: .code)
        XCTAssertTrue(entry.searchHints.contains("sql"))
        XCTAssertTrue(entry.searchHints.contains("database"))
        XCTAssertTrue(entry.searchHints.contains("postgres"))
        XCTAssertTrue(entry.searchHints.contains("mysql"))
    }

    func testSearchHintsForCodeWithInsertSQL() {
        let entry = makeEntry(content: "INSERT INTO users VALUES (1, 'Alice')", kind: .code)
        XCTAssertTrue(entry.searchHints.contains("sql"))
    }

    func testSearchHintsForCodeWithUpdateSQL() {
        let entry = makeEntry(content: "UPDATE users SET name = 'Bob' WHERE id = 1", kind: .code)
        XCTAssertTrue(entry.searchHints.contains("sql"))
    }

    func testSearchHintsForCodeWithDeleteSQL() {
        let entry = makeEntry(content: "DELETE FROM users WHERE id = 1", kind: .code)
        XCTAssertTrue(entry.searchHints.contains("sql"))
    }

    func testSearchHintsForCodeWithJoinSQL() {
        let entry = makeEntry(content: "SELECT u.name FROM users u JOIN orders o ON u.id = o.user_id", kind: .code)
        XCTAssertTrue(entry.searchHints.contains("sql"))
    }

    func testSearchHintsForCodeWithGroupBySQL() {
        let entry = makeEntry(content: "SELECT count(*) FROM users GROUP BY status", kind: .code)
        XCTAssertTrue(entry.searchHints.contains("sql"))
    }

    func testSearchHintsForCodeWithOrderBySQL() {
        let entry = makeEntry(content: "SELECT * FROM users ORDER BY created_at", kind: .code)
        XCTAssertTrue(entry.searchHints.contains("sql"))
    }

    func testSearchHintsForAllKindIsEmpty() {
        // The `.all` kind is a filter, not typically assigned to entries,
        // but if it were, hints should be minimal
        let entry = makeEntry(content: "test", kind: .all)
        // Should only contain "all"
        XCTAssertEqual(entry.searchHints, "all")
    }

    // MARK: - searchableText

    func testSearchableTextCombinesAllFields() {
        let entry = ClipboardEntry(
            id: "1",
            content: "hello world",
            date: Date(),
            sourceApp: "Terminal",
            kind: .text,
            imagePath: nil,
            ocrText: "ocr-content",
            isOCRPending: false
        )

        let text = entry.searchableText
        XCTAssertTrue(text.contains("hello world"))
        XCTAssertTrue(text.contains("terminal"))
        XCTAssertTrue(text.contains("ocr-content"))
        XCTAssertTrue(text.contains("text"))
        XCTAssertTrue(text.contains("note"))
    }

    func testSearchableTextIsLowercased() {
        let entry = makeEntry(content: "HELLO WORLD", kind: .text, sourceApp: "Xcode")
        let text = entry.searchableText
        XCTAssertEqual(text, text.lowercased())
    }

    func testSearchableTextHandlesNilSourceApp() {
        let entry = ClipboardEntry(
            id: "1",
            content: "test",
            date: Date(),
            sourceApp: nil,
            kind: .text,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )
        // Should not crash, and should contain empty string for sourceApp
        XCTAssertFalse(entry.searchableText.isEmpty)
    }

    // MARK: - Kind

    func testKindSymbolsAreDefined() {
        for kind in ClipboardEntry.Kind.allCases {
            XCTAssertFalse(kind.symbol.isEmpty, "Symbol for \(kind.rawValue) should not be empty")
        }
    }

    func testKindRawValues() {
        XCTAssertEqual(ClipboardEntry.Kind.all.rawValue, "All")
        XCTAssertEqual(ClipboardEntry.Kind.text.rawValue, "Text")
        XCTAssertEqual(ClipboardEntry.Kind.link.rawValue, "Link")
        XCTAssertEqual(ClipboardEntry.Kind.code.rawValue, "Code")
        XCTAssertEqual(ClipboardEntry.Kind.path.rawValue, "Path")
        XCTAssertEqual(ClipboardEntry.Kind.image.rawValue, "Image")
    }

    func testKindIdentifiable() {
        for kind in ClipboardEntry.Kind.allCases {
            XCTAssertEqual(kind.id, kind.rawValue)
        }
    }

    func testKindRawValueRoundtrip() {
        for kind in ClipboardEntry.Kind.allCases {
            let recovered = ClipboardEntry.Kind(rawValue: kind.rawValue)
            XCTAssertEqual(recovered, kind)
        }
    }

    // MARK: - Hashable / Identifiable

    func testEntryIsHashable() {
        let fixedDate = Date(timeIntervalSince1970: 1000)
        let a = makeEntry(id: "1", content: "hello", kind: .text, date: fixedDate)
        let b = makeEntry(id: "1", content: "hello", kind: .text, date: fixedDate)
        let c = makeEntry(id: "2", content: "hello", kind: .text, date: fixedDate)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)

        var set = Set<ClipboardEntry>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Helpers

    private func makeEntry(
        id: String = "test",
        content: String,
        kind: ClipboardEntry.Kind,
        date: Date = Date(),
        imagePath: String? = nil,
        ocrText: String = "",
        isOCRPending: Bool = false,
        sourceApp: String? = "Test"
    ) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            content: content,
            date: date,
            sourceApp: sourceApp,
            kind: kind,
            imagePath: imagePath,
            ocrText: ocrText,
            isOCRPending: isOCRPending
        )
    }
}
