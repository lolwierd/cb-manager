import XCTest
@testable import CBManager

final class VisibleEntryWindowTests: XCTestCase {
    func testExpandedLimitIncludesSelectionOutsideCurrentWindow() {
        let limit = VisibleEntryWindow.expandedLimit(
            currentLimit: 100,
            totalCount: 450,
            targetIndex: 220,
            pageSize: 200
        )

        XCTAssertEqual(limit, 400)
    }

    func testExpandedLimitDoesNotGrowWhenSelectionAlreadyVisible() {
        let limit = VisibleEntryWindow.expandedLimit(
            currentLimit: 100,
            totalCount: 450,
            targetIndex: 72,
            pageSize: 200
        )

        XCTAssertEqual(limit, 100)
    }

    func testVisualEntryOrderMatchesRenderedDateSections() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let today = calendar.startOfDay(for: Date())
        let yesterday = today.addingTimeInterval(-86_400)
        let earlier = today.addingTimeInterval(-86_400 * 10)

        let entries = [
            makeEntry(id: "today-ranked-first", date: today.addingTimeInterval(60)),
            makeEntry(id: "earlier-ranked-second", date: earlier),
            makeEntry(id: "today-ranked-third", date: today),
            makeEntry(id: "yesterday-ranked-fourth", date: yesterday)
        ]

        let ids = VisualEntryOrder.idsByDateSections(from: entries, calendar: calendar)

        XCTAssertEqual(ids, [
            "today-ranked-first",
            "today-ranked-third",
            "yesterday-ranked-fourth",
            "earlier-ranked-second"
        ])
    }

    private func makeEntry(id: String, date: Date) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            content: id,
            date: date,
            sourceApp: "Tests",
            kind: .text,
            imagePath: nil,
            ocrText: "",
            isOCRPending: false
        )
    }
}
