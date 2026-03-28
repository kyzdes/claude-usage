import XCTest
@testable import CCUsageViewer

final class ANSIStreamParserTests: XCTestCase {
    func testParserRendersTrustPromptAfterCursorMoves() {
        let transcript = """
        \u{001B}[1CAccessing\u{001B}[1Cworkspace:\r
        \r
        \u{001B}[1CQuick\u{001B}[1Csafety\u{001B}[1Ccheck:\r
        \u{001B}[1C1.\u{001B}[1CYes,\u{001B}[1CI\u{001B}[1Ctrust\u{001B}[1Cthis\u{001B}[1Cfolder\r
        """

        var parser = ANSIStreamParser(width: 80, height: 12)
        parser.consume(Data(transcript.utf8))
        let rendered = parser.screenBuffer.renderedText()

        XCTAssertTrue(rendered.contains("Accessing workspace:"))
        XCTAssertTrue(rendered.contains("Quick safety check:"))
        XCTAssertTrue(rendered.contains("Yes, I trust this folder"))
    }

    func testParserHandlesEraseLineAndCursorRepositioning() {
        let transcript = """
        Old value\r\u{001B}[2KCurrent session\r
        \u{001B}[10G20% used
        """

        var parser = ANSIStreamParser(width: 80, height: 6)
        parser.consume(Data(transcript.utf8))
        let rendered = parser.screenBuffer.renderedText()

        XCTAssertFalse(rendered.contains("Old value"))
        XCTAssertTrue(rendered.contains("Current session"))
        XCTAssertTrue(rendered.contains("20% used"))
    }
}
