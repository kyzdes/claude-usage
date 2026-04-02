import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    let viewModel: LimitViewModel
    @ObservedObject var authService: WebAuthService

    var body: some View {
        Form {
            Section("Data Source") {
                Picker("Preferred source", selection: $appModel.preferredDataSource) {
                    ForEach(DataSourcePreference.allCases, id: \.rawValue) { pref in
                        Text(pref.title).tag(pref)
                    }
                }

                if authService.hasCredentials {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected to Claude.ai API")
                            .font(.caption)
                        Spacer()
                        Button("Logout") {
                            authService.logout()
                        }
                        .controlSize(.small)
                    }
                } else {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                        Text("Not connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(authService.isAuthenticating ? "Waiting for login…" : "Login to Claude.ai") {
                            authService.startLogin()
                        }
                        .disabled(authService.isAuthenticating)
                        .controlSize(.small)
                    }

                    if let error = authService.authError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Appearance") {
                Toggle("Compact menu bar (% + timer)", isOn: $appModel.compactMenuBarMode)
            }

            Section("Notifications") {
                Toggle("Usage alerts", isOn: $appModel.notificationsEnabled)

                Stepper(value: $appModel.warnThreshold, in: 1...99) {
                    HStack {
                        Circle().fill(.orange).frame(width: 8, height: 8)
                        Text("Warn at \(appModel.warnThreshold)%")
                    }
                }

                Stepper(value: $appModel.dangerThreshold, in: 1...99) {
                    HStack {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("Danger at \(appModel.dangerThreshold)%")
                    }
                }
            }

            Section("Refresh") {
                Toggle("Auto refresh", isOn: $appModel.autoRefreshEnabled)

                Stepper(value: $appModel.refreshIntervalMinutes, in: 1...60) {
                    Text("Refresh every \(appModel.refreshIntervalMinutes) min")
                }

                Stepper(value: $appModel.staleThresholdMinutes, in: 1...180) {
                    Text("Mark stale after \(appModel.staleThresholdMinutes) min")
                }
            }

            Section("History") {
                if let historyStore = viewModel.historyStore {
                    LabeledContent("Stored samples") {
                        Text("\(historyStore.sampleCount())")
                            .font(.caption.monospacedDigit())
                    }

                    Button("Clear All History", role: .destructive) {
                        historyStore.deleteAllSamples()
                    }
                    .controlSize(.small)
                } else {
                    Text("History not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                Toggle("Show raw capture in popover", isOn: $appModel.showRawCapture)

                LabeledContent("Claude working dir") {
                    Text(appModel.claudeWorkingDirectoryDescription)
                        .font(.caption.monospaced())
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }

                Button("Run capture now") {
                    Task {
                        await viewModel.refresh(forceVisibleLoading: true)
                    }
                }

                if let errorMessage = viewModel.claudeLastErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if appModel.showRawCapture {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Raw capture")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(viewModel.claudeDiagnosticsText.isEmpty ? "No capture text yet." : viewModel.claudeDiagnosticsText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 120)
                    }
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
