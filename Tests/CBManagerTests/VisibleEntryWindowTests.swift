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
}
