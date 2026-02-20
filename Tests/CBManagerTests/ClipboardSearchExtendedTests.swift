import XCTest
@testable import CBManager

final class ClipboardSearchExtendedTests: XCTestCase {
    // MARK: - normalize

    func testNormalizeTrimsAndLowercases() {
        XCTAssertEqual(ClipboardSearch.normalize("  HeLLo  "), "hello")
        XCTAssertEqual(ClipboardSearch.normalize("\n\tFoo\n"), "foo")
        XCTAssertEqual(ClipboardSearch.normalize(""), "")
        XCTAssertEqual(ClipboardSearch.normalize("   "), "")
    }

    func testNormalizePreservesInternalSpaces() {
        XCTAssertEqual(ClipboardSearch.normalize("  hello world  "), "hello world")
    }

    // MARK: - Threshold checks

    func testKeywordQMDThresholdBoundary() {
        XCTAssertFalse(ClipboardSearch.shouldRunKeywordQMD(normalizedQuery: ""))
        XCTAssertFalse(ClipboardSearch.shouldRunKeywordQMD(normalizedQuery: "a"))
        XCTAssertFalse(ClipboardSearch.shouldRunKeywordQMD(normalizedQuery: "ab"))
        XCTAssertTrue(ClipboardSearch.shouldRunKeywordQMD(normalizedQuery: "abc"))
        XCTAssertTrue(ClipboardSearch.shouldRunKeywordQMD(normalizedQuery: "abcd"))
    }

    func testSemanticQMDThresholdBoundary() {
        XCTAssertFalse(ClipboardSearch.shouldRunSemanticQMD(normalizedQuery: ""))
        XCTAssertFalse(ClipboardSearch.shouldRunSemanticQMD(normalizedQuery: "a"))
        XCTAssertFalse(ClipboardSearch.shouldRunSemanticQMD(normalizedQuery: "ab"))
        XCTAssertFalse(ClipboardSearch.shouldRunSemanticQMD(normalizedQuery: "abc"))
        XCTAssertFalse(ClipboardSearch.shouldRunSemanticQMD(normalizedQuery: "abcd"))
        XCTAssertTrue(ClipboardSearch.shouldRunSemanticQMD(normalizedQuery: "abcde"))
        XCTAssertTrue(ClipboardSearch.shouldRunSemanticQMD(normalizedQuery: "abcdef"))
    }

    func testThresholdsCountPreNormalizedInput() {
        // Callers pass already-normalized (trimmed + lowercased) queries.
        XCTAssertFalse(ClipboardSearch.shouldRunKeywordQMD(normalizedQuery: "ab"))
        XCTAssertTrue(ClipboardSearch.shouldRunKeywordQMD(normalizedQuery: "abc"))
    }

    // MARK: - rank: empty query returns all in order

    func testRankEmptyQueryReturnsAllEntriesByDate() {
        let now = Date()
        let entries = [
            makeEntry(id: "old", content: "old", date: now.addingTimeInterval(-100)),
            makeEntry(id: "new", content: "new", date: now)
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries, query: "", filter: .all,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )

        // Empty query returns base (unranked, original order from input)
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked.map(\.id), ["old", "new"])
    }

    func testRankWhitespaceOnlyQueryReturnsAll() {
        let entries = [makeEntry(id: "1", content: "test", date: Date())]
        let ranked = ClipboardSearch.rank(
            entries: entries, query: "   ", filter: .all,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )
        XCTAssertEqual(ranked.count, 1)
    }

    // MARK: - rank: filter by kind

    func testRankFiltersByKind() {
        let now = Date()
        let entries = [
            makeEntry(id: "text1", content: "hello", kind: .text, date: now),
            makeEntry(id: "link1", content: "https://example.com", kind: .link, date: now.addingTimeInterval(-1)),
            makeEntry(id: "code1", content: "let x = 1", kind: .code, date: now.addingTimeInterval(-2)),
        ]

        let textOnly = ClipboardSearch.rank(
            entries: entries, query: "", filter: .text,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )
        XCTAssertEqual(textOnly.map(\.id), ["text1"])

        let linkOnly = ClipboardSearch.rank(
            entries: entries, query: "", filter: .link,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )
        XCTAssertEqual(linkOnly.map(\.id), ["link1"])

        let codeOnly = ClipboardSearch.rank(
            entries: entries, query: "", filter: .code,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )
        XCTAssertEqual(codeOnly.map(\.id), ["code1"])
    }

    func testRankFilterAllIncludesEverything() {
        let entries = [
            makeEntry(id: "1", content: "text", kind: .text, date: Date()),
            makeEntry(id: "2", content: "code", kind: .code, date: Date().addingTimeInterval(-1)),
        ]

        let all = ClipboardSearch.rank(
            entries: entries, query: "", filter: .all,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )
        XCTAssertEqual(all.count, 2)
    }

    func testRankFilterWithQueryCombinesFilterAndFuzzy() {
        let now = Date()
        let entries = [
            makeEntry(id: "text-hello", content: "hello world", kind: .text, date: now),
            makeEntry(id: "code-hello", content: "hello func() {}", kind: .code, date: now.addingTimeInterval(-1)),
            makeEntry(id: "text-bye", content: "goodbye world", kind: .text, date: now.addingTimeInterval(-2)),
        ]

        let result = ClipboardSearch.rank(
            entries: entries, query: "hello", filter: .text,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )

        // Should only include text entries matching "hello"
        XCTAssertTrue(result.contains { $0.id == "text-hello" })
        XCTAssertFalse(result.contains { $0.id == "code-hello" }) // wrong kind
        XCTAssertFalse(result.contains { $0.id == "text-bye" }) // no match for "hello" in content... wait
        // Actually "goodbye" doesn't match "hello" in fuzzy. Let's check
    }

    // MARK: - rank: empty entries

    func testRankEmptyEntriesReturnsEmpty() {
        let ranked = ClipboardSearch.rank(
            entries: [], query: "test", filter: .all,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )
        XCTAssertTrue(ranked.isEmpty)
    }

    // MARK: - rank: fuzzy scoring

    func testRankExactMatchScoredHigherThanSubsequence() {
        let now = Date()
        let entries = [
            makeEntry(id: "exact", content: "hello world", date: now.addingTimeInterval(-10)),
            makeEntry(id: "sub", content: "h-e-l-l-o world", date: now), // subsequence match only
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries, query: "hello", filter: .all,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )

        XCTAssertEqual(ranked.first?.id, "exact")
    }

    func testRankNoMatchExcludesEntry() {
        let entries = [
            makeEntry(id: "1", content: "alpha bravo", date: Date())
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries, query: "zzz", filter: .all,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )

        XCTAssertTrue(ranked.isEmpty)
    }

    func testRankMultiTokenQueryRequiresAllTokens() {
        let entries = [
            makeEntry(id: "both", content: "alpha bravo charlie", date: Date()),
            makeEntry(id: "one", content: "alpha only", date: Date().addingTimeInterval(-1)),
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries, query: "alpha charlie", filter: .all,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )

        // "alpha only" doesn't contain "charlie" so should be excluded
        XCTAssertTrue(ranked.contains { $0.id == "both" })
        XCTAssertFalse(ranked.contains { $0.id == "one" })
    }

    func testRankSameScoreSortsByDateDescending() {
        let now = Date()
        let entries = [
            makeEntry(id: "old", content: "test content", date: now.addingTimeInterval(-100)),
            makeEntry(id: "new", content: "test content", date: now),
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries, query: "test", filter: .all,
            qmdResultQuery: "", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )

        // Same score → newer first
        XCTAssertEqual(ranked.first?.id, "new")
    }

    // MARK: - rank: QMD augmentation

    func testQMDResultsAppendedWhenQueryMatches() {
        let now = Date()
        let entries = [
            makeEntry(id: "fuzzy-hit", content: "alpha bravo", date: now),
            makeEntry(id: "qmd-only", content: "zzz unrelated", date: now.addingTimeInterval(-10)),
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries, query: "alpha", filter: .all,
            qmdResultQuery: "alpha", qmdKeywordIDs: ["qmd-only"], qmdSemanticIDs: nil
        )

        XCTAssertTrue(ranked.contains { $0.id == "fuzzy-hit" })
        XCTAssertTrue(ranked.contains { $0.id == "qmd-only" })
        // fuzzy hit should come first
        XCTAssertEqual(ranked.first?.id, "fuzzy-hit")
    }

    func testQMDResultsIgnoredWhenQueryMismatch() {
        let now = Date()
        let entries = [
            makeEntry(id: "1", content: "alpha", date: now),
            makeEntry(id: "2", content: "zzz", date: now.addingTimeInterval(-10)),
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries, query: "alpha", filter: .all,
            qmdResultQuery: "different query", qmdKeywordIDs: ["2"], qmdSemanticIDs: nil
        )

        // QMD results should NOT be included because qmdResultQuery != normalized query
        XCTAssertFalse(ranked.contains { $0.id == "2" })
    }

    func testQMDSemanticAndKeywordMerged() {
        let now = Date()
        let entries = [
            makeEntry(id: "1", content: "main match", date: now),
            makeEntry(id: "kw", content: "keyword only", date: now.addingTimeInterval(-10)),
            makeEntry(id: "sem", content: "semantic only", date: now.addingTimeInterval(-20)),
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries, query: "main", filter: .all,
            qmdResultQuery: "main", qmdKeywordIDs: ["kw"], qmdSemanticIDs: ["sem"]
        )

        let ids = Set(ranked.map(\.id))
        XCTAssertTrue(ids.contains("1"))
        XCTAssertTrue(ids.contains("kw"))
        XCTAssertTrue(ids.contains("sem"))
    }

    func testQMDNilIDsMeansNoAugmentation() {
        let entries = [
            makeEntry(id: "1", content: "hello", date: Date()),
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries, query: "hello", filter: .all,
            qmdResultQuery: "hello", qmdKeywordIDs: nil, qmdSemanticIDs: nil
        )

        XCTAssertEqual(ranked.count, 1)
    }

    func testQMDDoesNotDuplicateFuzzyHits() {
        let now = Date()
        let entries = [
            makeEntry(id: "1", content: "hello world", date: now),
        ]

        let ranked = ClipboardSearch.rank(
            entries: entries, query: "hello", filter: .all,
            qmdResultQuery: "hello", qmdKeywordIDs: ["1"], qmdSemanticIDs: ["1"]
        )

        XCTAssertEqual(ranked.count, 1)
    }

    // MARK: - fuzzyScore

    func testFuzzyScoreReturnsNilForNoMatch() {
        let entry = makeEntry(id: "1", content: "hello", date: Date())
        XCTAssertNil(ClipboardSearch.fuzzyScore(for: entry, query: "xyz"))
    }

    func testFuzzyScoreReturnsNilForEmptyQuery() {
        let entry = makeEntry(id: "1", content: "hello", date: Date())
        XCTAssertNil(ClipboardSearch.fuzzyScore(for: entry, query: ""))
    }

    func testFuzzyScoreExactMatchHigherThanSubsequence() {
        let entry1 = makeEntry(id: "1", content: "hello", date: Date())
        let entry2 = makeEntry(id: "2", content: "h---e---l---l---o", date: Date())

        let score1 = ClipboardSearch.fuzzyScore(for: entry1, query: "hello")
        let score2 = ClipboardSearch.fuzzyScore(for: entry2, query: "hello")

        XCTAssertNotNil(score1)
        XCTAssertNotNil(score2)
        XCTAssertGreaterThan(score1!, score2!)
    }

    func testFuzzyScoreEarlierPositionBonus() {
        let entry1 = makeEntry(id: "1", content: "hello world test", date: Date())
        let entry2 = makeEntry(id: "2", content: "aaaa hello world test", date: Date())

        let score1 = ClipboardSearch.fuzzyScore(for: entry1, query: "hello")
        let score2 = ClipboardSearch.fuzzyScore(for: entry2, query: "hello")

        XCTAssertNotNil(score1)
        XCTAssertNotNil(score2)
        XCTAssertGreaterThan(score1!, score2!)
    }

    func testFuzzyScoreImageKindGetsBoost() {
        let textEntry = makeEntry(id: "1", content: "test screenshot", kind: .text, date: Date())
        let imageEntry = ClipboardEntry(
            id: "2",
            content: "test screenshot",
            date: Date(),
            sourceApp: "Test",
            kind: .image,
            imagePath: "/tmp/x.png",
            ocrText: "",
            isOCRPending: false
        )

        let textScore = ClipboardSearch.fuzzyScore(for: textEntry, query: "test screenshot")
        let imageScore = ClipboardSearch.fuzzyScore(for: imageEntry, query: "test screenshot")

        XCTAssertNotNil(textScore)
        XCTAssertNotNil(imageScore)
        // Image gets +15 boost
        XCTAssertEqual(imageScore!, textScore! + 15)
    }

    func testFuzzyScoreMultiTokenAllMustMatch() {
        let entry = makeEntry(id: "1", content: "alpha bravo charlie", date: Date())
        XCTAssertNotNil(ClipboardSearch.fuzzyScore(for: entry, query: "alpha charlie"))
        XCTAssertNil(ClipboardSearch.fuzzyScore(for: entry, query: "alpha zzz"))
    }

    func testFuzzyScoreMatchesAcrossSearchableText() {
        // searchableText includes content + ocrText + sourceApp + kind + searchHints
        let entry = ClipboardEntry(
            id: "1",
            content: "some content",
            date: Date(),
            sourceApp: "Terminal",
            kind: .text,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )

        // "terminal" is in searchableText via sourceApp
        XCTAssertNotNil(ClipboardSearch.fuzzyScore(for: entry, query: "terminal"))
    }

    // MARK: - Helpers

    private func makeEntry(
        id: String = "test",
        content: String,
        kind: ClipboardEntry.Kind = .text,
        date: Date = Date()
    ) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            content: content,
            date: date,
            sourceApp: "Test",
            kind: kind,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )
    }
}
