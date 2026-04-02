import SwiftUI

struct CountdownTimerView: View {
    let resetsAt: Date?
    let windowDurationMinutes: Int
    let warnThreshold: Int
    let dangerThreshold: Int

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 3.5)

            // Elapsed progress ring
            Circle()
                .trim(from: 0, to: elapsedFraction)
                .stroke(timerColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Countdown text
            Text(countdownText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(timerColor)
        }
        .frame(width: 48, height: 48)
        .onReceive(timer) { now = $0 }
    }

    private var remainingSeconds: TimeInterval {
        guard let resetsAt else { return 0 }
        return max(0, resetsAt.timeIntervalSince(now))
    }

    private var elapsedFraction: CGFloat {
        guard let resetsAt else { return 0 }
        let totalSeconds = Double(windowDurationMinutes) * 60
        guard totalSeconds > 0 else { return 0 }
        let elapsed = totalSeconds - resetsAt.timeIntervalSince(now)
        return CGFloat(min(max(elapsed / totalSeconds, 0), 1))
    }

    private var elapsedPercent: Double {
        Double(elapsedFraction) * 100
    }

    private var timerColor: Color {
        if elapsedPercent >= Double(dangerThreshold) {
            return .red
        } else if elapsedPercent >= Double(warnThreshold) {
            return .orange
        }
        return .green
    }

    private var countdownText: String {
        guard resetsAt != nil else { return "--" }
        let total = Int(remainingSeconds)
        guard total > 0 else { return "0m" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours >= 24 {
            let days = hours / 24
            let h = hours % 24
            return "\(days)d\(h)h"
        } else if hours > 0 {
            return "\(hours)h\(minutes)m"
        } else {
            let seconds = total % 60
            return "\(minutes)m\(seconds)s"
        }
    }
}
