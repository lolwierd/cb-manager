import XCTest
@testable import CBManager

@MainActor
final class LifecycleDiagnosticsTests: XCTestCase {
    private func makeState(
        uptimeSeconds: Double = 3_600,
        lastHeartbeatAt: Double = 1_000_000,
        exitReason: String? = nil
    ) -> LifecycleSessionState {
        LifecycleSessionState(
            sessionID: "session",
            pid: 4242,
            version: "1.0.1",
            startedAt: lastHeartbeatAt - uptimeSeconds,
            lastHeartbeatAt: lastHeartbeatAt,
            uptimeSeconds: uptimeSeconds,
            footprintMB: 812.5,
            peakFootprintMB: 900,
            threadCount: 31,
            openFileDescriptors: 96,
            entryCount: 18_402,
            exitReason: exitReason
        )
    }

    func testVerdictFlagsAMissingExitReasonAsAKill() {
        let verdict = LifecycleDiagnostics.verdict(
            for: makeState(),
            now: 1_000_600
        )

        XCTAssertTrue(verdict.contains("DIED WITHOUT CLEAN EXIT"))
        // The counters as of the last heartbeat are what make the report useful.
        XCTAssertTrue(verdict.contains("footprintMB=812.5"))
        XCTAssertTrue(verdict.contains("peakMB=900.0"))
        XCTAssertTrue(verdict.contains("entries=18402"))
        XCTAssertTrue(verdict.contains("threads=31"))
        XCTAssertTrue(verdict.contains("fds=96"))
        XCTAssertTrue(verdict.contains("deadFor=10m"))
    }

    func testVerdictReportsAnOrderlyShutdown() {
        let verdict = LifecycleDiagnostics.verdict(
            for: makeState(exitReason: "applicationWillTerminate"),
            now: 1_000_600
        )

        XCTAssertTrue(verdict.contains("ended cleanly"))
        XCTAssertTrue(verdict.contains("reason=applicationWillTerminate"))
        XCTAssertFalse(verdict.contains("DIED WITHOUT CLEAN EXIT"))
    }

    func testFormatUptimeRollsUpToDays() {
        XCTAssertEqual(LifecycleDiagnostics.formatUptime(0), "0m")
        XCTAssertEqual(LifecycleDiagnostics.formatUptime(90), "1m")
        XCTAssertEqual(LifecycleDiagnostics.formatUptime(3_660), "1h1m")
        XCTAssertEqual(LifecycleDiagnostics.formatUptime(4 * 86_400 + 7_260), "4d2h1m")
        XCTAssertEqual(LifecycleDiagnostics.formatUptime(-1), "unknown")
    }
}
