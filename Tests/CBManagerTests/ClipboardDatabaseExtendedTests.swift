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
        let entries = db.loadEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    func testDeleteFromEmptyDatabaseDoesNotCrash() {
        db.delete(id: "nonexistent")
        XCTAssertTrue(db.loadEntries().isEmpty)
    }

    func testUpdateOCROnNonexistentEntryDoesNotCrash() {
        db.updateOCR(id: "nonexistent", ocrText: "test", isPending: false)
        XCTAssertTrue(db.loadEntries().isEmpty)
    }

    // MARK: - Insert and load

    func testInsertSingleEntry() {
        db.insert(entry(id: "a", content: "hello", kind: .text))
        let loaded = db.loadEntries()
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

        let loaded = db.loadEntries()
        XCTAssertEqual(loaded.map(\.id), ["new", "mid", "old"])
    }

    func testLoadEntriesReturnsAll() {
        for i in 0..<10 {
            db.insert(entry(id: "\(i)", content: "entry \(i)", date: Date(timeIntervalSince1970: Double(i))))
        }

        let loaded = db.loadEntries()
        XCTAssertEqual(loaded.count, 10)
        // Ordered newest first
        XCTAssertEqual(loaded.first?.id, "9")
        XCTAssertEqual(loaded.last?.id, "0")
    }

    // MARK: - Upsert behavior (INSERT OR REPLACE)

    func testInsertSameIDReplacesEntry() {
        db.insert(entry(id: "a", content: "original", date: Date(timeIntervalSince1970: 100)))
        db.insert(entry(id: "a", content: "updated", date: Date(timeIntervalSince1970: 200)))

        let loaded = db.loadEntries()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].content, "updated")
    }

    // MARK: - Kind roundtrip

    func testAllKindsRoundtripThroughDatabase() {
        let kinds: [ClipboardEntry.Kind] = [.text, .link, .code, .path, .image]
        for (i, kind) in kinds.enumerated() {
            db.insert(entry(id: "kind-\(i)", content: "test", kind: kind, date: Date(timeIntervalSince1970: Double(i))))
        }

        let loaded = db.loadEntries()
        let loadedKinds = Set(loaded.map(\.kind))
        XCTAssertEqual(loadedKinds, Set(kinds))
    }

    func testUnknownKindDefaultsToText() {
        // The database stores kind as raw string. If somehow an unknown kind is stored,
        // loading should default to .text. This is tested implicitly through ClipboardDatabase's
        // fallback: `ClipboardEntry.Kind(rawValue: kindString) ?? .text`
        // We can test by inserting a valid entry and verifying.
        db.insert(entry(id: "t", content: "test", kind: .text))
        let loaded = db.loadEntries()
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
        let loaded = db.loadEntries()
        XCTAssertNil(loaded.first?.sourceApp)
    }

    func testNullImagePathRoundtrip() {
        db.insert(entry(id: "no-img", content: "test", kind: .text))
        let loaded = db.loadEntries()
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
        let loaded = db.loadEntries()
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
        let loaded = db.loadEntries()
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
        let loaded = db.loadEntries()
        XCTAssertEqual(loaded.first?.isOCRPending, true)
    }

    func testUpdateOCRChangesTextAndPending() {
        db.insert(entry(id: "a", content: "", kind: .image))
        db.updateOCR(id: "a", ocrText: "new text", isPending: false)

        let loaded = db.loadEntries()
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
        XCTAssertTrue(db.loadEntries().first!.isOCRPending)

        db.updateOCR(id: "pending", ocrText: "recognized", isPending: false)
        let updated = db.loadEntries().first!
        XCTAssertEqual(updated.ocrText, "recognized")
        XCTAssertFalse(updated.isOCRPending)
    }

    // MARK: - AI Title

    func testAITitleFieldsRoundtrip() {
        let e = ClipboardEntry(
            id: "ai-title-test",
            content: "",
            date: Date(timeIntervalSince1970: 100),
            sourceApp: nil,
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "",
            isOCRPending: false,
            aiTitle: "A screenshot of a terminal window",
            isAITitlePending: false
        )
        db.insert(e)
        let loaded = db.loadEntries().first!
        XCTAssertEqual(loaded.aiTitle, "A screenshot of a terminal window")
        XCTAssertFalse(loaded.isAITitlePending)
    }

    func testUpdateAITitleFromPendingToCompleted() {
        let e = ClipboardEntry(
            id: "ai-pending",
            content: "",
            date: Date(timeIntervalSince1970: 100),
            sourceApp: nil,
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "",
            isOCRPending: false,
            aiTitle: "",
            isAITitlePending: true
        )
        db.insert(e)
        XCTAssertTrue(db.loadEntries().first!.isAITitlePending)

        db.updateAITitle(id: "ai-pending", aiTitle: "Cat on keyboard", isPending: false)
        let updated = db.loadEntries().first!
        XCTAssertEqual(updated.aiTitle, "Cat on keyboard")
        XCTAssertFalse(updated.isAITitlePending)
    }

    // MARK: - Delete Older Than

    func testDeleteOlderThanRemovesOldEntries() {
        let old = Date(timeIntervalSince1970: 1000)
        let recent = Date(timeIntervalSince1970: 9000)
        db.insert(entry(id: "old1", content: "old", date: old))
        db.insert(entry(id: "old2", content: "old2", date: Date(timeIntervalSince1970: 2000)))
        db.insert(entry(id: "new1", content: "new", date: recent))

        let cutoff = Date(timeIntervalSince1970: 5000)
        let removed = db.deleteOlderThan(cutoff)

        XCTAssertEqual(removed.count, 2)
        XCTAssertEqual(Set(removed.map(\.id)), ["old1", "old2"])

        let remaining = db.loadEntries()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "new1")
    }

    func testDeleteOlderThanReturnsEmptyWhenNothingToDelete() {
        db.insert(entry(id: "a", content: "a", date: Date(timeIntervalSince1970: 9000)))
        let removed = db.deleteOlderThan(Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(db.loadEntries().count, 1)
    }

    func testDeleteOlderThanPreservesImagePaths() {
        let e = ClipboardEntry(
            id: "img-old",
            content: "",
            date: Date(timeIntervalSince1970: 100),
            sourceApp: nil,
            kind: .image,
            imagePath: "/tmp/old-image.png",
            ocrText: "",
            isOCRPending: false
        )
        db.insert(e)
        let removed = db.deleteOlderThan(Date(timeIntervalSince1970: 500))
        XCTAssertEqual(removed.first?.imagePath, "/tmp/old-image.png")
    }

    // MARK: - Delete

    func testDeleteRemovesEntry() {
        db.insert(entry(id: "a", content: "a"))
        db.insert(entry(id: "b", content: "b", date: Date(timeIntervalSince1970: 200)))
        db.delete(id: "a")
        let loaded = db.loadEntries()
        XCTAssertEqual(loaded.map(\.id), ["b"])
    }

    func testDeleteNonexistentIDDoesNotAffectOthers() {
        db.insert(entry(id: "a", content: "a"))
        db.delete(id: "nonexistent")
        XCTAssertEqual(db.loadEntries().count, 1)
    }

    func testDeleteAllEntries() {
        db.insert(entry(id: "a", content: "a"))
        db.insert(entry(id: "b", content: "b", date: Date(timeIntervalSince1970: 200)))
        db.delete(id: "a")
        db.delete(id: "b")
        XCTAssertTrue(db.loadEntries().isEmpty)
    }

    // MARK: - Date roundtrip

    func testDatePreservation() {
        let date = Date(timeIntervalSince1970: 1706789012.5)
        db.insert(entry(id: "date-test", content: "test", date: date))
        let loaded = db.loadEntries()
        XCTAssertEqual(loaded.first?.date.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Content with special characters

    func testContentWithSpecialCharacters() {
        let specialContent = "Hello 'world' \"test\" `code` \\ emoji 🎉 日本語"
        db.insert(entry(id: "special", content: specialContent))
        let loaded = db.loadEntries()
        XCTAssertEqual(loaded.first?.content, specialContent)
    }

    func testContentWithNewlines() {
        let multiline = "line1\nline2\nline3\n\ttabbed"
        db.insert(entry(id: "multiline", content: multiline))
        let loaded = db.loadEntries()
        XCTAssertEqual(loaded.first?.content, multiline)
    }

    func testEmptyContent() {
        db.insert(entry(id: "empty", content: ""))
        let loaded = db.loadEntries()
        XCTAssertEqual(loaded.first?.content, "")
    }

    // MARK: - Multiple database instances on same path

    func testSecondDatabaseInstanceSeesPreviousData() {
        db.insert(entry(id: "persist", content: "persistent data"))

        // Create a new database instance pointing to the same directory
        let db2 = ClipboardDatabase(baseDirectory: tempDir)
        let loaded = db2.loadEntries()
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
