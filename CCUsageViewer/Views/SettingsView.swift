import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    let viewModel: LimitViewModel

    var body: some View {
        Form {
            Section("Refresh") {
                Toggle("Auto refresh", isOn: $appModel.autoRefreshEnabled)

                Stepper(value: $appModel.refreshIntervalMinutes, in: 1...60) {
                    Text("Refresh every \(appModel.refreshIntervalMinutes) min")
                }

                Stepper(value: $appModel.staleThresholdMinutes, in: 1...180) {
                    Text("Mark stale after \(appModel.staleThresholdMinutes) min")
                }
            }

            Section("Diagnostics") {
                Toggle("Show raw /usage capture in menu bar", isOn: $appModel.showRawCapture)

                LabeledContent("Claude working dir") {
                    Text(appModel.workingDirectoryDescription)
                        .font(.caption.monospaced())
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }

                Button("Run capture now") {
                    Task {
                        await viewModel.refresh(forceVisibleLoading: true)
                    }
                }

                if let errorMessage = viewModel.lastErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if appModel.showRawCapture {
                    ScrollView {
                        Text(viewModel.diagnosticsText.isEmpty ? "No capture text yet." : viewModel.diagnosticsText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 160)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onChange(of: appModel.refreshSettingsKey) { _, _ in
            viewModel.reconfigureAutoRefresh()
        }
    }
}
