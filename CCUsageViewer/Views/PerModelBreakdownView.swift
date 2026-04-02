import SwiftUI

struct PerModelBreakdownView: View {
    let models: [ModelLimitSection]
    let warnThreshold: Int
    let dangerThreshold: Int

    var body: some View {
        if !models.isEmpty {
            DisclosureGroup("Per-model breakdown") {
                VStack(spacing: 6) {
                    ForEach(models) { model in
                        HStack(spacing: 8) {
                            Text(model.modelName)
                                .font(.caption)
                                .frame(width: 90, alignment: .leading)

                            ProgressView(value: min(max(model.utilization, 0), 100), total: 100)
                                .tint(colorForUtilization(model.utilization))

                            Text("\(Int(model.utilization))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.subheadline)
        }
    }

    private func colorForUtilization(_ value: Double) -> Color {
        if value >= Double(dangerThreshold) {
            return .red
        } else if value >= Double(warnThreshold) {
            return .orange
        }
        return .green
    }
}
