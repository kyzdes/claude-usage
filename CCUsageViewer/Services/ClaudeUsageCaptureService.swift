import Darwin
import Foundation

protocol ClaudeUsageCaptureServiceProtocol: Sendable {
    func captureUsage() async throws -> UsageCaptureResult
}

enum ClaudeUsageCaptureError: LocalizedError, Equatable {
    case claudeNotInstalled
    case spawnFailed(Int32)
    case timeout(CaptureFlowPhase, String)
    case screenNotRecognized(String)
    case emptyCapture

    var errorDescription: String? {
        switch self {
        case .claudeNotInstalled:
            return "Claude CLI is not installed or not available in the app environment."
        case .spawnFailed(let code):
            return "Failed to launch Claude CLI. POSIX error: \(code)."
        case .timeout(let phase, let screenText):
            return "Timed out while waiting for Claude during \(phase.rawValue). Last visible text: \(screenText.compactScreenExcerpt)"
        case .screenNotRecognized(let screenText):
            return "Claude ran, but the /usage screen could not be recognized. Last visible text: \(screenText.compactScreenExcerpt)"
        case .emptyCapture:
            return "Claude exited before returning any visible terminal output."
        }
    }
}

private extension String {
    var compactScreenExcerpt: String {
        let normalized = replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            return "[empty]"
        }

        return String(normalized.prefix(220))
    }
}

struct ClaudeUsageCaptureService: ClaudeUsageCaptureServiceProtocol, Sendable {
    private let columns: UInt16
    private let rows: UInt16
    private let pollIntervalNanoseconds: UInt64
    private let totalTimeout: TimeInterval

    init(
        columns: UInt16 = 120,
        rows: UInt16 = 40,
        pollIntervalNanoseconds: UInt64 = 150_000_000,
        totalTimeout: TimeInterval = 35
    ) {
        self.columns = columns
        self.rows = rows
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.totalTimeout = totalTimeout
    }

    func captureUsage() async throws -> UsageCaptureResult {
        try await Task.detached(priority: .userInitiated) {
            try self.captureUsageSync()
        }.value
    }

    private func captureUsageSync() throws -> UsageCaptureResult {
        let executablePath = try findClaudeExecutable()
        let workingDirectory = try makeWorkingDirectory()
        let session = try startClaudeSession(executablePath: executablePath, workingDirectory: workingDirectory)
        var parser = ANSIStreamParser(width: Int(columns), height: Int(rows))
        var stateMachine = CaptureFlowStateMachine(now: .now)
        let captureStart = Date()

        defer {
            terminate(processID: session.processID)
            close(session.masterFD)
            _ = waitForProcessExit(processID: session.processID)
        }

        try setNonBlocking(fileDescriptor: session.masterFD)

        while Date().timeIntervalSince(captureStart) < totalTimeout {
            let now = Date()
            if let chunk = readAvailable(from: session.masterFD), !chunk.isEmpty {
                parser.consume(chunk)
            }

            let screenText = parser.screenBuffer.renderedText()
            if screenText.isEmpty, waitForProcessExit(processID: session.processID, shouldBlock: false) != nil {
                throw ClaudeUsageCaptureError.emptyCapture
            }

            let actions = stateMachine.evaluate(screenText: screenText, now: now)
            for action in actions {
                switch action {
                case .sendTrust:
                    try send("\r", to: session.masterFD)
                case .sendUsage:
                    try send("/usage\r", to: session.masterFD)
                case .captureCompleted:
                    return UsageCaptureResult(
                        capturedAt: now,
                        screenText: screenText,
                        rawScreenLines: parser.screenBuffer.renderedLines(),
                        sourceState: screenText.lowercased().contains("current session") ? .live : .partial
                    )
                }
            }

            if shouldTimeout(phase: stateMachine.phase, now: now, phaseEnteredAt: stateMachine.phaseEnteredAt) {
                throw ClaudeUsageCaptureError.timeout(stateMachine.phase, screenText)
            }

            if waitForProcessExit(processID: session.processID, shouldBlock: false) != nil {
                if screenText.lowercased().contains("current session")
                    || screenText.lowercased().contains("weekly") {
                    return UsageCaptureResult(
                        capturedAt: now,
                        screenText: screenText,
                        rawScreenLines: parser.screenBuffer.renderedLines(),
                        sourceState: .partial
                    )
                }

                throw ClaudeUsageCaptureError.screenNotRecognized(screenText)
            }

            Thread.sleep(forTimeInterval: Double(pollIntervalNanoseconds) / 1_000_000_000)
        }

        throw ClaudeUsageCaptureError.timeout(stateMachine.phase, parser.screenBuffer.renderedText())
    }

    private func shouldTimeout(phase: CaptureFlowPhase, now: Date, phaseEnteredAt: Date) -> Bool {
        let elapsed = now.timeIntervalSince(phaseEnteredAt)
        switch phase {
        case .launching, .awaitingTrustPrompt:
            return elapsed > 8
        case .awaitingReadyPrompt:
            return elapsed > 8
        case .awaitingUsageScreen:
            return elapsed > 16
        case .requestingUsage, .captured, .failed:
            return false
        }
    }

    private func makeWorkingDirectory() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CCUsageViewer/ClaudeCLI", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func findClaudeExecutable() throws -> String {
        let fm = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let homeDirectoryPath = FileManager.default.homeDirectoryForCurrentUser.path

        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .map { NSString(string: $0).appendingPathComponent("claude") }

        let commonCandidates = [
            "\(homeDirectoryPath)/.local/bin/claude",
            "\(homeDirectoryPath)/bin/claude",
            "\(homeDirectoryPath)/.npm-global/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]

        for candidate in pathCandidates + commonCandidates where fm.isExecutableFile(atPath: candidate) {
            return candidate
        }

        if let shellResolvedPath = shellResolvedClaudePath(),
           fm.isExecutableFile(atPath: shellResolvedPath) {
            return shellResolvedPath
        }

        throw ClaudeUsageCaptureError.claudeNotInstalled
    }

    private func shellResolvedClaudePath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return output.isEmpty ? nil : output
    }

    private func startClaudeSession(executablePath: String, workingDirectory: URL) throws -> (processID: pid_t, masterFD: Int32) {
        guard let executableCString = strdup(executablePath),
              let workingDirectoryCString = strdup(workingDirectory.path) else {
            throw ClaudeUsageCaptureError.spawnFailed(errno)
        }
        defer {
            free(executableCString)
            free(workingDirectoryCString)
        }

        var masterFD: Int32 = -1
        var windowSize = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        let processID = forkpty(&masterFD, nil, nil, &windowSize)

        if processID < 0 {
            throw ClaudeUsageCaptureError.spawnFailed(errno)
        }

        if processID == 0 {
            _ = chdir(workingDirectoryCString)
            _ = setenv("TERM", "xterm-256color", 1)
            let columnsString = String(columns)
            let rowsString = String(rows)
            columnsString.withCString { pointer in
                _ = setenv("COLUMNS", pointer, 1)
            }
            rowsString.withCString { pointer in
                _ = setenv("LINES", pointer, 1)
            }

            var arguments: [UnsafeMutablePointer<CChar>?] = [executableCString, nil]
            execv(executableCString, &arguments)
            _exit(127)
        }

        return (processID, masterFD)
    }

    private func readAvailable(from fileDescriptor: Int32) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(fileDescriptor, &buffer, buffer.count)
        if count > 0 {
            return Data(buffer.prefix(count))
        }

        if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK {
            return nil
        }

        return nil
    }

    private func send(_ input: String, to fileDescriptor: Int32) throws {
        let bytes = Array(input.utf8)
        let result = bytes.withUnsafeBytes { rawBuffer in
            write(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
        }

        if result < 0 {
            throw ClaudeUsageCaptureError.spawnFailed(errno)
        }
    }

    private func setNonBlocking(fileDescriptor: Int32) throws {
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags >= 0, fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw ClaudeUsageCaptureError.spawnFailed(errno)
        }
    }

    private func terminate(processID: pid_t) {
        guard processID > 0 else {
            return
        }

        kill(processID, SIGTERM)
        usleep(200_000)
        if waitForProcessExit(processID: processID, shouldBlock: false) == nil {
            kill(processID, SIGKILL)
        }
    }

    private func waitForProcessExit(processID: pid_t, shouldBlock: Bool = true) -> Int32? {
        var status: Int32 = 0
        let options: Int32 = shouldBlock ? 0 : WNOHANG
        let result = waitpid(processID, &status, options)
        return result == processID ? status : nil
    }
}
