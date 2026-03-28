import Foundation

struct TerminalScreenBuffer: Sendable {
    private let blank: Character = " "

    let width: Int
    let height: Int

    private(set) var cursorRow = 0
    private(set) var cursorColumn = 0
    private var grid: [[Character]]

    init(width: Int = 120, height: Int = 40) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.grid = Array(
            repeating: Array(repeating: " ", count: max(1, width)),
            count: max(1, height)
        )
    }

    mutating func put(_ character: Character) {
        guard cursorRow >= 0, cursorRow < height, cursorColumn >= 0, cursorColumn < width else {
            return
        }

        grid[cursorRow][cursorColumn] = character
        advanceCursor()
    }

    mutating func carriageReturn() {
        cursorColumn = 0
    }

    mutating func lineFeed() {
        if cursorRow == height - 1 {
            scrollUp()
        } else {
            cursorRow += 1
        }
    }

    mutating func backspace() {
        cursorColumn = max(0, cursorColumn - 1)
    }

    mutating func moveCursorUp(_ amount: Int) {
        cursorRow = max(0, cursorRow - max(1, amount))
    }

    mutating func moveCursorDown(_ amount: Int) {
        cursorRow = min(height - 1, cursorRow + max(1, amount))
    }

    mutating func moveCursorForward(_ amount: Int) {
        cursorColumn = min(width - 1, cursorColumn + max(1, amount))
    }

    mutating func moveCursorBackward(_ amount: Int) {
        cursorColumn = max(0, cursorColumn - max(1, amount))
    }

    mutating func moveCursorTo(row: Int, column: Int) {
        cursorRow = min(max(0, row), height - 1)
        cursorColumn = min(max(0, column), width - 1)
    }

    mutating func cursorHorizontalAbsolute(_ column: Int) {
        cursorColumn = min(max(0, column), width - 1)
    }

    mutating func cursorVerticalAbsolute(_ row: Int) {
        cursorRow = min(max(0, row), height - 1)
    }

    mutating func eraseLine(mode: Int) {
        switch mode {
        case 1:
            fillLine(from: 0, through: cursorColumn)
        case 2:
            fillLine(from: 0, through: width - 1)
        default:
            fillLine(from: cursorColumn, through: width - 1)
        }
    }

    mutating func eraseDisplay(mode: Int) {
        switch mode {
        case 1:
            for row in 0...cursorRow {
                let endColumn = row == cursorRow ? cursorColumn : width - 1
                fillRow(row, from: 0, through: endColumn)
            }
        case 2, 3:
            for row in 0..<height {
                fillRow(row, from: 0, through: width - 1)
            }
            moveCursorTo(row: 0, column: 0)
        default:
            for row in cursorRow..<height {
                let startColumn = row == cursorRow ? cursorColumn : 0
                fillRow(row, from: startColumn, through: width - 1)
            }
        }
    }

    func renderedLines() -> [String] {
        grid.map { line in
            String(line).trimmingTrailingWhitespace()
        }
    }

    func renderedText() -> String {
        renderedLines()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func advanceCursor() {
        if cursorColumn == width - 1 {
            cursorColumn = 0
            lineFeed()
        } else {
            cursorColumn += 1
        }
    }

    private mutating func scrollUp() {
        grid.removeFirst()
        grid.append(Array(repeating: blank, count: width))
    }

    private mutating func fillLine(from start: Int, through end: Int) {
        fillRow(cursorRow, from: start, through: end)
    }

    private mutating func fillRow(_ row: Int, from start: Int, through end: Int) {
        guard row >= 0, row < height, start <= end else {
            return
        }

        let lowerBound = max(0, start)
        let upperBound = min(width - 1, end)
        guard lowerBound <= upperBound else {
            return
        }

        for index in lowerBound...upperBound {
            grid[row][index] = blank
        }
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        replacingOccurrences(
            of: #"\s+$"#,
            with: "",
            options: .regularExpression
        )
    }
}
