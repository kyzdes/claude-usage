import XCTest
@testable import CCUsageViewer

final class UsageScreenParserTests: XCTestCase {
    func testParserExtractsPlanCurrentSessionAndWeeklyLimit() throws {
        let screen = """
        Claude Max

        Current session
        42% used
        58% remaining
        Resets in 2h 14m

        Weekly
        81% used
        19% remaining
        Resets on Apr 1
        """

        let snapshot = try UsageScreenParser().parse(
            screenText: screen,
            capturedAt: Date(timeIntervalSince1970: 3_000)
        )

        XCTAssertEqual(snapshot.planName, "Claude Max")
        XCTAssertEqual(snapshot.currentSession?.progressPercent, 42.0)
        XCTAssertEqual(snapshot.currentSession?.remainingText, "58% remaining")
        XCTAssertEqual(snapshot.currentSession?.resetText, "Resets in 2h 14m")
        XCTAssertEqual(snapshot.weeklyLimit?.progressPercent, 81.0)
        XCTAssertEqual(snapshot.weeklyLimit?.remainingText, "19% remaining")
        XCTAssertFalse(snapshot.isPartial)
    }

    func testParserReturnsPartialSnapshotWhenOnlyCurrentSessionExists() throws {
        let screen = """
        ╭ Claude Max ╮
        Current session
        64% used
        Resets tomorrow
        """

        let snapshot = try UsageScreenParser().parse(
            screenText: screen,
            capturedAt: Date(timeIntervalSince1970: 4_000)
        )

        XCTAssertEqual(snapshot.planName, "Claude Max")
        XCTAssertEqual(snapshot.currentSession?.progressPercent, 64.0)
        XCTAssertNil(snapshot.weeklyLimit)
        XCTAssertFalse(snapshot.isPartial)
    }

    func testParserRecognizesCurrentWeekAllModelsAsWeeklyLimit() throws {
        let screen = """
        kyzdes5@gmail.com's Organization

        Current session
        45% used
        Resets 10pm (Europe/Moscow)

        Current week (all models)
        7% used
        Resets Apr 4 at 2pm (Europe/Moscow)

        Current week (Sonnet only)
        1% used
        Resets Mar 30 at 10pm (Europe/Moscow)
        """

        let snapshot = try UsageScreenParser().parse(
            screenText: screen,
            capturedAt: Date(timeIntervalSince1970: 5_000)
        )

        XCTAssertEqual(snapshot.currentSession?.progressPercent, 45.0)
        XCTAssertEqual(snapshot.weeklyLimit?.title, "Current week")
        XCTAssertEqual(snapshot.weeklyLimit?.progressPercent, 7.0)
        XCTAssertEqual(snapshot.weeklyLimit?.usedText, "7% used")
        XCTAssertEqual(snapshot.weeklyLimit?.resetText, "Resets Apr 4 at 2pm (Europe/Moscow)")
    }

    func testParserThrowsForUnrelatedScreen() {
        XCTAssertThrowsError(
            try UsageScreenParser().parse(
                screenText: "Claude Code\n/help for help",
                capturedAt: Date()
            )
        ) { error in
            XCTAssertEqual(error as? UsageScreenParserError, .missingUsageMarkers)
        }
    }
}
