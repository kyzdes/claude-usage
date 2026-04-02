import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    let viewModel: LimitViewModel
    @ObservedObject var authService: WebAuthService
    @FocusState private var focusedField: String?
    @State private var showPtyRiskAlert = false
    @State private var pendingDataSource: DataSourcePreference?

    var body: some View {
        Form {
            Section("Data Source") {
                Picker("Preferred source", selection: Binding(
                    get: { appModel.preferredDataSource },
                    set: { newValue in
                        if newValue.needsRiskAcceptance {
                            pendingDataSource = newValue
                            showPtyRiskAlert = true
                        } else {
                            appModel.preferredDataSource = newValue
                        }
                    }
                )) {
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

                HStack {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                    Text("Warn at")
                    Spacer()
                    TextField("", value: $appModel.warnThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: "warn")
                    Text("%")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Danger at")
                    Spacer()
                    TextField("", value: $appModel.dangerThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: "danger")
                    Text("%")
                        .foregroundStyle(.secondary)
                }

                Button("Send test notification") {
                    Task {
                        await viewModel.notificationManager.sendTestNotification()
                    }
                }
                .controlSize(.small)
            }

            Section("Refresh") {
                Toggle("Auto refresh", isOn: $appModel.autoRefreshEnabled)

                HStack {
                    Text("Refresh every")
                    Spacer()
                    TextField("", value: $appModel.refreshIntervalMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: "interval")
                    Text("min")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Mark stale after")
                    Spacer()
                    TextField("", value: $appModel.staleThresholdMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: "stale")
                    Text("min")
                        .foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            // Monitor clicks — resign first responder when clicking outside text fields
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                if let window = NSApp.keyWindow,
                   let firstResponder = window.firstResponder,
                   firstResponder is NSTextView {
                    // Check if click is NOT on a text field
                    let location = event.locationInWindow
                    if let hitView = window.contentView?.hitTest(location),
                       !(hitView is NSTextField) {
                        window.makeFirstResponder(nil)
                    }
                }
                return event
            }
        }
        .onChange(of: appModel.refreshSettingsKey) { _, _ in
            viewModel.reconfigureAutoRefresh()
        }
        .alert("PTY Capture Risk", isPresented: $showPtyRiskAlert) {
            Button("Accept Risk") {
                if let pending = pendingDataSource {
                    appModel.preferredDataSource = pending
                    appModel.logPtyRiskAcceptance()
                }
                pendingDataSource = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDataSource = nil
            }
        } message: {
            Text("PTY mode launches Claude CLI in a terminal session. This may be unstable, consume extra resources, and break with CLI updates.\n\nAPI mode is recommended for reliable usage tracking.")
        }
    }
}
