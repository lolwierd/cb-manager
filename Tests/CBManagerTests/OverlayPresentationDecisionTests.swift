import XCTest
@testable import CBManager

final class OverlayPresentationDecisionTests: XCTestCase {
    func testVisibleActivePresentationTogglesClosed() {
        XCTAssertTrue(
            OverlayPresentationDecision.shouldHide(
                isPresented: true,
                panelVisible: true,
                appActive: true
            )
        )
    }

    func testZombieVisibleInactivePanelTogglesOpen() {
        XCTAssertFalse(
            OverlayPresentationDecision.shouldHide(
                isPresented: true,
                panelVisible: true,
                appActive: false
            )
        )
    }

    func testInternallyPresentedButMissingPanelTogglesOpen() {
        XCTAssertFalse(
            OverlayPresentationDecision.shouldHide(
                isPresented: true,
                panelVisible: false,
                appActive: true
            )
        )
    }
}
