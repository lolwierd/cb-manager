import XCTest
@testable import CBManager

final class ClipboardSearchTests: XCTestCase {
    func testNormalizeAndThresholds() {
        XCTAssertEqual(ClipboardSearch.normalize("  HeLLo  "), "hello")
        XCTAssertFalse(ClipboardSearch.shouldRunKeywordQMD(query: "ab"))
        XCTAssertTrue(ClipboardSearch.shouldRunKeywordQMD(query: "abc"))
        XCTAssertFalse(ClipboardSearch.shouldRunSemanticQMD(query: "abc"))
        XCTAssertFalse(ClipboardSearch.shouldRunSemanticQMD(query: "abcd"))
        XCTAssertTrue(ClipboardSearch.shouldRunSemanticQMD(query: "abcde"))
    }

    func testFuzzyRankingPrioritizesCloserMatch() {
        let now = Date()
        let entries = [
            makeEntry(id: "1", content: "kubectl config current-context", date: now.addingTimeInterval(-10)),
            makeEntry(id: "2", content: "git checkout -b feature", date: now)
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries,
            query: "kub cont",
            filter: .all,
            qmdResultQuery: "",
            qmdKeywordIDs: nil,
            qmdSemanticIDs: nil
        )

        XCTAssertEqual(ranked.first?.id, "1")
    }

    func testQMDAugmentsFuzzyWithoutDuplicates() {
        let now = Date()
        let entries = [
            makeEntry(id: "1", content: "alpha bravo", date: now.addingTimeInterval(-20)),
            makeEntry(id: "2", content: "charlie delta", date: now.addingTimeInterval(-10)),
            makeEntry(id: "3", content: "echo foxtrot", date: now)
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries,
            query: "alpha",
            filter: .all,
            qmdResultQuery: "alpha",
            qmdKeywordIDs: ["2", "3"],
            qmdSemanticIDs: ["3"]
        )

        XCTAssertEqual(Set(ranked.map(\.id)), Set(["1", "2", "3"]))
        XCTAssertEqual(ranked.filter { $0.id == "3" }.count, 1)
    }

    func testQueryTermMatchesSQLCodeViaHints() {
        let now = Date()
        let sqlEntry = ClipboardEntry(
            id: "sql",
            content: "SELECT * FROM volumes WHERE id = 7",
            date: now,
            sourceApp: "DBConsole",
            kind: .code,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )
        let otherEntry = makeEntry(id: "txt", content: "hello world", date: now.addingTimeInterval(-1))

        let ranked = ClipboardSearch.rank(
            entries: [sqlEntry, otherEntry],
            query: "query",
            filter: .all,
            qmdResultQuery: "",
            qmdKeywordIDs: nil,
            qmdSemanticIDs: nil
        )

        XCTAssertEqual(ranked.first?.id, "sql")
    }

    private func makeEntry(id: String, content: String, date: Date) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            content: content,
            date: date,
            sourceApp: "Test",
            kind: .text,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )
    }
}
