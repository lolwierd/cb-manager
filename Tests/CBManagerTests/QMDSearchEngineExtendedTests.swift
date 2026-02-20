import XCTest
@testable import CBManager

final class QMDSearchEngineExtendedTests: XCTestCase {
    // MARK: - parseIDs

    func testParseIDsFromValidJSON() {
        let json = """
        [
          {"file":"qmd://cbmanager/abc-123.md"},
          {"file":"qmd://cbmanager/def-456.md"}
        ]
        """
        let ids = QMDSearchEngine.parseIDs(from: json)
        XCTAssertEqual(ids, Set(["abc-123", "def-456"]))
    }

    func testParseIDsDeduplicates() {
        let json = """
        [
          {"file":"qmd://cbmanager/abc.md"},
          {"file":"qmd://cbmanager/abc.md"},
          {"file":"qmd://cbmanager/abc.md"}
        ]
        """
        let ids = QMDSearchEngine.parseIDs(from: json)
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(ids, Set(["abc"]))
    }

    func testParseIDsWithEmptyArray() {
        let ids = QMDSearchEngine.parseIDs(from: "[]")
        XCTAssertTrue(ids.isEmpty)
    }

    func testParseIDsWithInvalidJSON() {
        XCTAssertTrue(QMDSearchEngine.parseIDs(from: "not json").isEmpty)
        XCTAssertTrue(QMDSearchEngine.parseIDs(from: "").isEmpty)
        XCTAssertTrue(QMDSearchEngine.parseIDs(from: "{\"key\": \"value\"}").isEmpty)
    }

    func testParseIDsWithNullFileField() {
        let json = """
        [
          {"file": null},
          {"file": "qmd://cbmanager/valid-id.md"}
        ]
        """
        let ids = QMDSearchEngine.parseIDs(from: json)
        XCTAssertEqual(ids, Set(["valid-id"]))
    }

    func testParseIDsWithMissingFileField() {
        let json = """
        [
          {"other_field": "value"},
          {"file": "qmd://cbmanager/valid.md"}
        ]
        """
        let ids = QMDSearchEngine.parseIDs(from: json)
        XCTAssertEqual(ids, Set(["valid"]))
    }

    func testParseIDsStripsPathPrefix() {
        let json = """
        [
          {"file": "qmd://cbmanager/deep/nested/entry-id.md"}
        ]
        """
        let ids = QMDSearchEngine.parseIDs(from: json)
        // parseIDs takes the last path component and strips .md
        XCTAssertEqual(ids, Set(["entry-id"]))
    }

    func testParseIDsHandlesUUIDs() {
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        let json = """
        [{"file":"qmd://cbmanager/\(uuid).md"}]
        """
        let ids = QMDSearchEngine.parseIDs(from: json)
        XCTAssertEqual(ids, Set([uuid]))
    }

    func testParseIDsWithExtraFields() {
        let json = """
        [
          {"file":"qmd://cbmanager/id1.md", "score": 0.95, "title": "test"},
          {"file":"qmd://cbmanager/id2.md", "score": 0.80}
        ]
        """
        let ids = QMDSearchEngine.parseIDs(from: json)
        XCTAssertEqual(ids, Set(["id1", "id2"]))
    }

    func testParseIDsWithSpecialCharactersInID() {
        let json = """
        [{"file":"qmd://cbmanager/entry_with-special.chars.md"}]
        """
        let ids = QMDSearchEngine.parseIDs(from: json)
        XCTAssertEqual(ids, Set(["entry_with-special.chars"]))
    }

    func testParseIDsLargeResultSet() {
        var rows: [String] = []
        for i in 0..<100 {
            rows.append("{\"file\":\"qmd://cbmanager/id-\(i).md\"}")
        }
        let json = "[\(rows.joined(separator: ","))]"
        let ids = QMDSearchEngine.parseIDs(from: json)
        XCTAssertEqual(ids.count, 100)
    }
}
