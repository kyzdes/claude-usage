import XCTest
@testable import CCUsageViewer

final class CaptureFlowStateMachineTrustPersistenceTests: XCTestCase {
    func testStateMachineRetriesTrustConfirmationIfPromptStillVisible() {
        let start = Date(timeIntervalSince1970: 5_000)
        var stateMachine = CaptureFlowStateMachine(now: start)

        _ = stateMachine.evaluate(
            screenText: "Quick safety check\n1. Yes, I trust this folder",
            now: start
        )

        let retryActions = stateMachine.evaluate(
            screenText: "Quick safety check\n1. Yes, I trust this folder",
            now: start.addingTimeInterval(1.1)
        )

        XCTAssertEqual(retryActions.first, .sendTrust)
        XCTAssertEqual(stateMachine.phase, .awaitingReadyPrompt)
    }

    func testStateMachineEventuallyRequestsUsageAfterTrustRetries() {
        let start = Date(timeIntervalSince1970: 6_000)
        var stateMachine = CaptureFlowStateMachine(now: start)

        _ = stateMachine.evaluate(
            screenText: "Quick safety check\n1. Yes, I trust this folder",
            now: start
        )
        _ = stateMachine.evaluate(
            screenText: "Quick safety check\n1. Yes, I trust this folder",
            now: start.addingTimeInterval(1.1)
        )

        let usageActions = stateMachine.evaluate(
            screenText: "Quick safety check\n1. Yes, I trust this folder",
            now: start.addingTimeInterval(3.8)
        )

        XCTAssertEqual(usageActions.first, .sendUsage)
        XCTAssertEqual(stateMachine.phase, .awaitingUsageScreen)
    }
}
