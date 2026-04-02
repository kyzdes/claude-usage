import XCTest
@testable import CCUsageViewer

final class CaptureFlowStateMachineTests: XCTestCase {
    func testStateMachineTrustThenUsageCapture() {
        let start = Date(timeIntervalSince1970: 1_000)
        var stateMachine = CaptureFlowStateMachine(now: start)

        let trustActions = stateMachine.evaluate(
            screenText: "Quick safety check\n1. Yes, I trust this folder",
            now: start
        )
        XCTAssertEqual(trustActions.count, 1)
        XCTAssertEqual(trustActions.first, .sendTrust)
        XCTAssertEqual(stateMachine.phase, .awaitingReadyPrompt)

        let readyActions = stateMachine.evaluate(
            screenText: "Claude Code\nClaude Max\n/help for help",
            now: start.addingTimeInterval(3)
        )
        XCTAssertEqual(readyActions.first, .sendUsage)
        XCTAssertEqual(stateMachine.phase, .awaitingUsageScreen)

        let firstUsagePass = stateMachine.evaluate(
            screenText: "Claude Max\nCurrent session\n42% used\nResets in 2h",
            now: start.addingTimeInterval(4)
        )
        XCTAssertTrue(firstUsagePass.isEmpty)

        let settledUsagePass = stateMachine.evaluate(
            screenText: "Claude Max\nCurrent session\n42% used\nResets in 2h",
            now: start.addingTimeInterval(5.3)
        )
        XCTAssertEqual(settledUsagePass.first, .captureCompleted)
        XCTAssertEqual(stateMachine.phase, .captured)
    }

    func testStateMachineCanRequestUsageWithoutTrustPrompt() {
        let start = Date(timeIntervalSince1970: 2_000)
        var stateMachine = CaptureFlowStateMachine(now: start)

        _ = stateMachine.evaluate(
            screenText: "Claude Code\nClaude Max",
            now: start
        )
        let actions = stateMachine.evaluate(
            screenText: "Claude Code\nClaude Max",
            now: start.addingTimeInterval(1.2)
        )

        XCTAssertEqual(actions.first, .sendUsage)
        XCTAssertEqual(stateMachine.phase, .awaitingUsageScreen)
    }

    func testCaptureServiceExtractsPlanHintFromWelcomeScreen() {
        let planName = ClaudeUsageCaptureService.extractPlanHint(
            from: "Claude Code\nClaude Max\n/help for help"
        )

        XCTAssertEqual(planName, "Claude Max")
    }

    func testCaptureServiceLeavesPlanHintEmptyWhenUsageScreenHasNoPlan() {
        let planName = ClaudeUsageCaptureService.extractPlanHint(
            from: """
            kyzdes5@gmail.com's Organization

            Current session
            22% used
            Resets 3am (Europe/Moscow)
            """
        )

        XCTAssertNil(planName)
    }

}
