import SwiftUI
import Charts

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Usage Dashboard")
                    .font(.title2.bold())
                Spacer()
                Picker("Range", selection: $viewModel.timeRange) {
                    ForEach(DashboardTimeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Session usage chart
                    chartSection(
                        title: "Session Usage (5h)",
                        color: .blue,
                        keyPath: \.sessionPercent
                    )

                    // Weekly usage chart
                    chartSection(
                        title: "Weekly Usage (7d)",
                        color: .purple,
                        keyPath: \.weeklyPercent
                    )

                    // Per-model charts
                    if viewModel.samples.contains(where: { $0.sonnetPercent != nil }) {
                        chartSection(
                            title: "Sonnet (7d)",
                            color: .orange,
                            optionalKeyPath: \.sonnetPercent
                        )
                    }

                    if viewModel.samples.contains(where: { $0.opusPercent != nil }) {
                        chartSection(
                            title: "Opus (7d)",
                            color: .red,
                            optionalKeyPath: \.opusPercent
                        )
                    }

                    // Stats
                    HStack {
                        Text("Total samples: \(viewModel.sampleCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear All History", role: .destructive) {
                            viewModel.deleteAllHistory()
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            viewModel.loadSamples()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
        .onChange(of: viewModel.timeRange) { _, _ in
            viewModel.loadSamples()
        }
    }

    @ViewBuilder
    private func chartSection(
        title: String,
        color: Color,
        keyPath: KeyPath<UsageHistorySample, Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if viewModel.samples.count >= 2 {
                Chart {
                    ForEach(viewModel.samples, id: \.timestamp) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("%", sample[keyPath: keyPath])
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("%", sample[keyPath: keyPath])
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.2), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisValueLabel()
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                    }
                }
                .frame(height: 180)
            } else {
                Text("Not enough data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func chartSection(
        title: String,
        color: Color,
        optionalKeyPath: KeyPath<UsageHistorySample, Double?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            let filteredSamples = viewModel.samples.filter { $0[keyPath: optionalKeyPath] != nil }

            if filteredSamples.count >= 2 {
                Chart {
                    ForEach(filteredSamples, id: \.timestamp) { sample in
                        if let value = sample[keyPath: optionalKeyPath] {
                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("%", value)
                            )
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 150)
            } else {
                Text("Not enough data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
