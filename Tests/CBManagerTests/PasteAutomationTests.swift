import XCTest
@testable import CBManager

final class PasteAutomationTests: XCTestCase {
    func testPreflightFailsWhenClipboardWriteFails() {
        let preflight = PastePreflight(
            clipboardWriteSucceeded: false,
            hasTargetApp: true,
            targetAppIsCurrentApp: false,
            permissions: PastePermissionSnapshot(accessibilityTrusted: true, postEventAccess: true)
        )

        XCTAssertEqual(preflight.failure, .clipboardWriteFailed)
        XCTAssertFalse(preflight.canAttemptSyntheticPaste)
    }

    func testPreflightFailsWhenTargetAppIsMissing() {
        let preflight = PastePreflight(
            clipboardWriteSucceeded: true,
            hasTargetApp: false,
            targetAppIsCurrentApp: false,
            permissions: PastePermissionSnapshot(accessibilityTrusted: true, postEventAccess: true)
        )

        XCTAssertEqual(preflight.failure, .missingTargetApp)
    }

    func testPreflightPrioritizesAccessibilityBeforePostEventPermission() {
        let preflight = PastePreflight(
            clipboardWriteSucceeded: true,
            hasTargetApp: true,
            targetAppIsCurrentApp: false,
            permissions: PastePermissionSnapshot(accessibilityTrusted: false, postEventAccess: false)
        )

        XCTAssertEqual(preflight.failure, .missingAccessibilityPermission)
    }

    func testPreflightAllowsSyntheticPasteWhenAllRequirementsPass() {
        let preflight = PastePreflight(
            clipboardWriteSucceeded: true,
            hasTargetApp: true,
            targetAppIsCurrentApp: false,
            permissions: PastePermissionSnapshot(accessibilityTrusted: true, postEventAccess: true)
        )

        XCTAssertNil(preflight.failure)
        XCTAssertTrue(preflight.canAttemptSyntheticPaste)
    }
}
