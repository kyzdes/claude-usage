import SwiftUI
import Charts

struct MiniChartView: View {
    let samples: [UsageHistorySample]

    /// Max gap in seconds before we consider data "missing" and use dashed line
    private let gapThreshold: TimeInterval = 10 * 60 // 10 minutes

    var body: some View {
        if samples.count >= 2 {
            Chart {
                ForEach(segments, id: \.id) { segment in
                    ForEach(segment.samples, id: \.timestamp) { sample in
                        if segment.isGap {
                            // Dashed line for interpolated/missing data
                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Session %", sample.sessionPercent),
                                series: .value("Type", segment.id)
                            )
                            .foregroundStyle(Color.green.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        } else {
                            // Solid area + line for real data
                            AreaMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Session %", sample.sessionPercent)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.25), Color.green.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Session %", sample.sessionPercent),
                                series: .value("Type", segment.id)
                            )
                            .foregroundStyle(Color.green.opacity(0.9))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)%")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                }
            }
            .frame(height: 100)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    // MARK: - Segment splitting

    private struct ChartSegment: Identifiable {
        let id: String
        let samples: [UsageHistorySample]
        let isGap: Bool
    }

    private var segments: [ChartSegment] {
        guard samples.count >= 2 else { return [] }

        var result: [ChartSegment] = []
        var currentRun: [UsageHistorySample] = [samples[0]]
        var segIdx = 0

        for i in 1..<samples.count {
            let gap = samples[i].timestamp.timeIntervalSince(samples[i - 1].timestamp)

            if gap > gapThreshold {
                // Flush current solid run
                if currentRun.count >= 1 {
                    result.append(ChartSegment(id: "s\(segIdx)", samples: currentRun, isGap: false))
                    segIdx += 1
                }
                // Add gap segment (last point of prev run + first point of next run)
                result.append(ChartSegment(
                    id: "g\(segIdx)",
                    samples: [samples[i - 1], samples[i]],
                    isGap: true
                ))
                segIdx += 1
                currentRun = [samples[i]]
            } else {
                currentRun.append(samples[i])
            }
        }

        // Flush last run
        if !currentRun.isEmpty {
            result.append(ChartSegment(id: "s\(segIdx)", samples: currentRun, isGap: false))
        }

        return result
    }
}
