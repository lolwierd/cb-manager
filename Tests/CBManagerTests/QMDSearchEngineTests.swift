import XCTest
@testable import CBManager

final class QMDSearchEngineTests: XCTestCase {
    func testParseIDsFromQMDJSONOutput() {
        let json = """
        [
          {"file":"qmd://cbmanager/abc-123.md"},
          {"file":"qmd://cbmanager/def-456.md"},
          {"file":"qmd://cbmanager/def-456.md"}
        ]
        """

        let ids = QMDSearchEngine.parseIDs(from: json)
        XCTAssertEqual(ids, Set(["abc-123", "def-456"]))
    }

    func testParseIDsHandlesInvalidJSON() {
        let ids = QMDSearchEngine.parseIDs(from: "not-json")
        XCTAssertTrue(ids.isEmpty)
    }
}
