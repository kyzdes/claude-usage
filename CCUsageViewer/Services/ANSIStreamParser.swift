import Foundation

struct ANSIStreamParser: Sendable {
    private enum ParserState: Sendable {
        case normal
        case escape
        case csi(String)
        case osc
        case oscEscape
    }

    private(set) var screenBuffer: TerminalScreenBuffer
    private var state: ParserState = .normal

    init(width: Int = 120, height: Int = 40) {
        self.screenBuffer = TerminalScreenBuffer(width: width, height: height)
    }

    mutating func consume(_ bytes: ArraySlice<UInt8>) {
        for byte in bytes {
            consume(byte)
        }
    }

    mutating func consume(_ data: Data) {
        consume(ArraySlice(data))
    }

    private mutating func consume(_ byte: UInt8) {
        switch state {
        case .normal:
            handleNormal(byte)
        case .escape:
            handleEscape(byte)
        case .csi(let parameters):
            handleCSI(byte, parameters: parameters)
        case .osc:
            if byte == 0x07 {
                state = .normal
            } else if byte == 0x1B {
                state = .oscEscape
            }
        case .oscEscape:
            state = byte == 0x5C ? .normal : .osc
        }
    }

    private mutating func handleNormal(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            state = .escape
        case 0x08, 0x7F:
            screenBuffer.backspace()
        case 0x09:
            for _ in 0..<4 {
                screenBuffer.put(" ")
            }
        case 0x0A:
            screenBuffer.lineFeed()
        case 0x0D:
            screenBuffer.carriageReturn()
        case 0x20...0x7E:
            let scalar = UnicodeScalar(byte)
            screenBuffer.put(Character(String(scalar)))
        default:
            break
        }
    }

    private mutating func handleEscape(_ byte: UInt8) {
        switch byte {
        case 0x5B:
            state = .csi("")
        case 0x5D:
            state = .osc
        default:
            state = .normal
        }
    }

    private mutating func handleCSI(_ byte: UInt8, parameters: String) {
        let scalar = UnicodeScalar(byte)

        if (0x40...0x7E).contains(byte) {
            applyCSI(command: Character(String(scalar)), parameters: parameters)
            state = .normal
            return
        }

        if byte < 0x80 {
            state = .csi(parameters + String(scalar))
        } else {
            state = .normal
        }
    }

    private mutating func applyCSI(command: Character, parameters: String) {
        let values = parameters
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }

        func value(_ index: Int, default fallback: Int = 1) -> Int {
            guard values.indices.contains(index) else {
                return fallback
            }

            return values[index] == 0 ? fallback : values[index]
        }

        switch command {
        case "A":
            screenBuffer.moveCursorUp(value(0))
        case "B":
            screenBuffer.moveCursorDown(value(0))
        case "C":
            screenBuffer.moveCursorForward(value(0))
        case "D":
            screenBuffer.moveCursorBackward(value(0))
        case "E":
            screenBuffer.moveCursorDown(value(0))
            screenBuffer.carriageReturn()
        case "F":
            screenBuffer.moveCursorUp(value(0))
            screenBuffer.carriageReturn()
        case "G":
            screenBuffer.cursorHorizontalAbsolute(value(0) - 1)
        case "H", "f":
            screenBuffer.moveCursorTo(row: value(0) - 1, column: value(1) - 1)
        case "J":
            screenBuffer.eraseDisplay(mode: values.first ?? 0)
        case "K":
            screenBuffer.eraseLine(mode: values.first ?? 0)
        case "d":
            screenBuffer.cursorVerticalAbsolute(value(0) - 1)
        case "h", "l", "m", "q", "r", "s", "t", "u":
            break
        default:
            break
        }
    }
}
