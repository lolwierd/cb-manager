import XCTest
@testable import CBManager

final class ClipboardDatabaseTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cbmanager-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testInsertLoadDeleteAndPrune() {
        let db = ClipboardDatabase(baseDirectory: tempDir)

        let e1 = entry(id: "a", content: "first", date: Date(timeIntervalSince1970: 100))
        let e2 = entry(id: "b", content: "second", date: Date(timeIntervalSince1970: 200))
        let e3 = entry(id: "c", content: "third", date: Date(timeIntervalSince1970: 300))

        db.insert(e1)
        db.insert(e2)
        db.insert(e3)

        let loaded = db.loadEntries()
        XCTAssertEqual(loaded.map(\.id), ["c", "b", "a"])

        db.updateOCR(id: "c", ocrText: "detected text", isPending: false)
        let afterOCR = db.loadEntries()
        XCTAssertEqual(afterOCR.first?.ocrText, "detected text")

        db.delete(id: "b")
        XCTAssertEqual(db.loadEntries().map(\.id), ["c", "a"])
    }

    private func entry(id: String, content: String, date: Date) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            content: content,
            date: date,
            sourceApp: "Tests",
            kind: .text,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )
    }
}
