import XCTest
@testable import CBManager

final class ClipboardStoreQMDIntegrationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cbmanager-store-qmd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testQMDKeywordResultsAugmentLiveStoreSearch() async {
        let db = ClipboardDatabase(baseDirectory: tempDir)
        db.insert(makeEntry(id: "fuzzy-hit", content: "alpha bravo", date: Date(timeIntervalSince1970: 200)))
        db.insert(makeEntry(id: "qmd-only", content: "totally unrelated", date: Date(timeIntervalSince1970: 100)))

        let qmd = FakeQMDSearchEngine(
            available: true,
            keywordResults: ["alp": ["qmd-only"]],
            semanticResults: [:]
        )
        let baseDirectory = tempDir!

        let store = await MainActor.run {
            ClipboardStore(
                baseDirectory: baseDirectory,
                qmdSearchEngine: qmd,
                shouldStartMonitoring: false
            )
        }

        await waitUntil("QMD availability") {
            await MainActor.run { store.isQMDAvailable }
        }

        await MainActor.run {
            store.overlayDidOpen(resetSearch: false)
            store.query = "alp"
        }

        await waitUntil("QMD merged results") {
            await MainActor.run {
                store.filteredEntries.contains { $0.id == "qmd-only" }
            }
        }

        let ids = await MainActor.run { store.filteredEntries.map(\.id) }
        XCTAssertEqual(ids.first, "fuzzy-hit")
        XCTAssertTrue(ids.contains("qmd-only"))
    }

    private func makeEntry(id: String, content: String, date: Date) -> ClipboardEntry {
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

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(25),
        condition: @escaping () async -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
            try? await Task.sleep(for: pollInterval)
        }
        XCTFail("Timed out waiting for \(description)")
    }
}

private actor FakeQMDSearchEngine: ClipboardQMDSearching {
    let available: Bool
    let keywordResults: [String: Set<String>]
    let semanticResults: [String: Set<String>]

    init(
        available: Bool,
        keywordResults: [String: Set<String>],
        semanticResults: [String: Set<String>]
    ) {
        self.available = available
        self.keywordResults = keywordResults
        self.semanticResults = semanticResults
    }

    func isAvailable() async -> Bool {
        available
    }

    func bootstrap(entries: [ClipboardEntry]) async {}

    func upsert(_ entry: ClipboardEntry) async {}

    func remove(id: String) async {}

    func keywordSearchIDs(query: String, limit: Int) async -> Set<String> {
        keywordResults[query] ?? []
    }

    func semanticSearchIDs(query: String, limit: Int) async -> Set<String> {
        semanticResults[query] ?? []
    }
}
