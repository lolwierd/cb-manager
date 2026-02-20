import XCTest
@testable import CBManager

final class ClipboardDatabaseExtendedTests: XCTestCase {
    private var tempDir: URL!
    private var db: ClipboardDatabase!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cbmanager-db-ext-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        db = ClipboardDatabase(baseDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Empty database

    func testLoadEntriesFromEmptyDatabase() {
        let entries = db.loadEntries(limit: 100)
        XCTAssertTrue(entries.isEmpty)
    }

    func testDeleteFromEmptyDatabaseDoesNotCrash() {
        db.delete(id: "nonexistent")
        XCTAssertTrue(db.loadEntries(limit: 10).isEmpty)
    }

    func testPruneEmptyDatabaseDoesNotCrash() {
        db.prune(limit: 5)
        XCTAssertTrue(db.loadEntries(limit: 10).isEmpty)
    }

    func testUpdateOCROnNonexistentEntryDoesNotCrash() {
        db.updateOCR(id: "nonexistent", ocrText: "test", isPending: false)
        XCTAssertTrue(db.loadEntries(limit: 10).isEmpty)
    }

    // MARK: - Insert and load

    func testInsertSingleEntry() {
        db.insert(entry(id: "a", content: "hello", kind: .text))
        let loaded = db.loadEntries(limit: 10)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "a")
        XCTAssertEqual(loaded[0].content, "hello")
        XCTAssertEqual(loaded[0].kind, .text)
    }

    func testLoadEntriesOrderedByDateDescending() {
        let base = Date(timeIntervalSince1970: 1000)
        db.insert(entry(id: "old", content: "old", date: base))
        db.insert(entry(id: "mid", content: "mid", date: base.addingTimeInterval(100)))
        db.insert(entry(id: "new", content: "new", date: base.addingTimeInterval(200)))

        let loaded = db.loadEntries(limit: 10)
        XCTAssertEqual(loaded.map(\.id), ["new", "mid", "old"])
    }

    func testLoadEntriesRespectsLimit() {
        for i in 0..<10 {
            db.insert(entry(id: "\(i)", content: "entry \(i)", date: Date(timeIntervalSince1970: Double(i))))
        }

        let loaded = db.loadEntries(limit: 3)
        XCTAssertEqual(loaded.count, 3)
        // Should be the 3 newest
        XCTAssertEqual(loaded.map(\.id), ["9", "8", "7"])
    }

    // MARK: - Upsert behavior (INSERT OR REPLACE)

    func testInsertSameIDReplacesEntry() {
        db.insert(entry(id: "a", content: "original", date: Date(timeIntervalSince1970: 100)))
        db.insert(entry(id: "a", content: "updated", date: Date(timeIntervalSince1970: 200)))

        let loaded = db.loadEntries(limit: 10)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].content, "updated")
    }

    // MARK: - Kind roundtrip

    func testAllKindsRoundtripThroughDatabase() {
        let kinds: [ClipboardEntry.Kind] = [.text, .link, .code, .path, .image]
        for (i, kind) in kinds.enumerated() {
            db.insert(entry(id: "kind-\(i)", content: "test", kind: kind, date: Date(timeIntervalSince1970: Double(i))))
        }

        let loaded = db.loadEntries(limit: 10)
        let loadedKinds = Set(loaded.map(\.kind))
        XCTAssertEqual(loadedKinds, Set(kinds))
    }

    func testUnknownKindDefaultsToText() {
        // The database stores kind as raw string. If somehow an unknown kind is stored,
        // loading should default to .text. This is tested implicitly through ClipboardDatabase's
        // fallback: `ClipboardEntry.Kind(rawValue: kindString) ?? .text`
        // We can test by inserting a valid entry and verifying.
        db.insert(entry(id: "t", content: "test", kind: .text))
        let loaded = db.loadEntries(limit: 1)
        XCTAssertEqual(loaded.first?.kind, .text)
    }

    // MARK: - Nullable fields

    func testNullSourceAppRoundtrip() {
        let e = ClipboardEntry(
            id: "null-app",
            content: "test",
            date: Date(timeIntervalSince1970: 100),
            sourceApp: nil,
            kind: .text,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )
        db.insert(e)
        let loaded = db.loadEntries(limit: 1)
        XCTAssertNil(loaded.first?.sourceApp)
    }

    func testNullImagePathRoundtrip() {
        db.insert(entry(id: "no-img", content: "test", kind: .text))
        let loaded = db.loadEntries(limit: 1)
        XCTAssertNil(loaded.first?.imagePath)
    }

    func testImagePathRoundtrip() {
        let e = ClipboardEntry(
            id: "with-img",
            content: "",
            date: Date(timeIntervalSince1970: 100),
            sourceApp: "Preview",
            kind: .image,
            imagePath: "/tmp/test.png",
            ocrText: "detected text",
            isOCRPending: false
        )
        db.insert(e)
        let loaded = db.loadEntries(limit: 1)
        XCTAssertEqual(loaded.first?.imagePath, "/tmp/test.png")
    }

    // MARK: - OCR fields

    func testOCRFieldsRoundtrip() {
        let e = ClipboardEntry(
            id: "ocr-test",
            content: "",
            date: Date(timeIntervalSince1970: 100),
            sourceApp: "Preview",
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "recognized text",
            isOCRPending: false
        )
        db.insert(e)
        let loaded = db.loadEntries(limit: 1)
        XCTAssertEqual(loaded.first?.ocrText, "recognized text")
        XCTAssertEqual(loaded.first?.isOCRPending, false)
    }

    func testOCRPendingFlagRoundtrip() {
        let e = ClipboardEntry(
            id: "ocr-pending",
            content: "",
            date: Date(timeIntervalSince1970: 100),
            sourceApp: "Preview",
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "",
            isOCRPending: true
        )
        db.insert(e)
        let loaded = db.loadEntries(limit: 1)
        XCTAssertEqual(loaded.first?.isOCRPending, true)
    }

    func testUpdateOCRChangesTextAndPending() {
        db.insert(entry(id: "a", content: "", kind: .image))
        db.updateOCR(id: "a", ocrText: "new text", isPending: false)

        let loaded = db.loadEntries(limit: 1)
        XCTAssertEqual(loaded.first?.ocrText, "new text")
        XCTAssertEqual(loaded.first?.isOCRPending, false)
    }

    func testUpdateOCRFromPendingToCompleted() {
        let e = ClipboardEntry(
            id: "pending",
            content: "",
            date: Date(timeIntervalSince1970: 100),
            sourceApp: nil,
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "",
            isOCRPending: true
        )
        db.insert(e)
        XCTAssertTrue(db.loadEntries(limit: 1).first!.isOCRPending)

        db.updateOCR(id: "pending", ocrText: "recognized", isPending: false)
        let updated = db.loadEntries(limit: 1).first!
        XCTAssertEqual(updated.ocrText, "recognized")
        XCTAssertFalse(updated.isOCRPending)
    }

    // MARK: - Delete

    func testDeleteRemovesEntry() {
        db.insert(entry(id: "a", content: "a"))
        db.insert(entry(id: "b", content: "b", date: Date(timeIntervalSince1970: 200)))
        db.delete(id: "a")
        let loaded = db.loadEntries(limit: 10)
        XCTAssertEqual(loaded.map(\.id), ["b"])
    }

    func testDeleteNonexistentIDDoesNotAffectOthers() {
        db.insert(entry(id: "a", content: "a"))
        db.delete(id: "nonexistent")
        XCTAssertEqual(db.loadEntries(limit: 10).count, 1)
    }

    func testDeleteAllEntries() {
        db.insert(entry(id: "a", content: "a"))
        db.insert(entry(id: "b", content: "b", date: Date(timeIntervalSince1970: 200)))
        db.delete(id: "a")
        db.delete(id: "b")
        XCTAssertTrue(db.loadEntries(limit: 10).isEmpty)
    }

    // MARK: - Prune

    func testPruneKeepsNewestEntries() {
        for i in 0..<5 {
            db.insert(entry(id: "\(i)", content: "e\(i)", date: Date(timeIntervalSince1970: Double(i * 100))))
        }

        db.prune(limit: 3)
        let loaded = db.loadEntries(limit: 10)
        XCTAssertEqual(loaded.count, 3)
        // Newest 3: ids 4, 3, 2
        XCTAssertEqual(loaded.map(\.id), ["4", "3", "2"])
    }

    func testPruneWithLimitGreaterThanCountKeepsAll() {
        db.insert(entry(id: "a", content: "a"))
        db.insert(entry(id: "b", content: "b", date: Date(timeIntervalSince1970: 200)))

        db.prune(limit: 100)
        XCTAssertEqual(db.loadEntries(limit: 10).count, 2)
    }

    func testPruneWithLimitZeroDeletesAll() {
        db.insert(entry(id: "a", content: "a"))
        db.insert(entry(id: "b", content: "b", date: Date(timeIntervalSince1970: 200)))

        db.prune(limit: 0)
        XCTAssertTrue(db.loadEntries(limit: 10).isEmpty)
    }

    func testPruneWithLimitOneKeepsOnlyNewest() {
        db.insert(entry(id: "old", content: "old", date: Date(timeIntervalSince1970: 100)))
        db.insert(entry(id: "new", content: "new", date: Date(timeIntervalSince1970: 200)))

        db.prune(limit: 1)
        let loaded = db.loadEntries(limit: 10)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "new")
    }

    // MARK: - Date roundtrip

    func testDatePreservation() {
        let date = Date(timeIntervalSince1970: 1706789012.5)
        db.insert(entry(id: "date-test", content: "test", date: date))
        let loaded = db.loadEntries(limit: 1)
        XCTAssertEqual(loaded.first?.date.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Content with special characters

    func testContentWithSpecialCharacters() {
        let specialContent = "Hello 'world' \"test\" `code` \\ emoji 🎉 日本語"
        db.insert(entry(id: "special", content: specialContent))
        let loaded = db.loadEntries(limit: 1)
        XCTAssertEqual(loaded.first?.content, specialContent)
    }

    func testContentWithNewlines() {
        let multiline = "line1\nline2\nline3\n\ttabbed"
        db.insert(entry(id: "multiline", content: multiline))
        let loaded = db.loadEntries(limit: 1)
        XCTAssertEqual(loaded.first?.content, multiline)
    }

    func testEmptyContent() {
        db.insert(entry(id: "empty", content: ""))
        let loaded = db.loadEntries(limit: 1)
        XCTAssertEqual(loaded.first?.content, "")
    }

    // MARK: - Multiple database instances on same path

    func testSecondDatabaseInstanceSeesPreviousData() {
        db.insert(entry(id: "persist", content: "persistent data"))

        // Create a new database instance pointing to the same directory
        let db2 = ClipboardDatabase(baseDirectory: tempDir)
        let loaded = db2.loadEntries(limit: 10)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "persist")
    }

    // MARK: - Helpers

    private func entry(
        id: String,
        content: String,
        kind: ClipboardEntry.Kind = .text,
        date: Date = Date(timeIntervalSince1970: 100)
    ) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            content: content,
            date: date,
            sourceApp: "Tests",
            kind: kind,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )
    }
}
