import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var appModel: AppModel
    let viewModel: LimitViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
            Divider()
            footer
        }
        .frame(width: 380)
        .padding(16)
        .onChange(of: appModel.refreshSettingsKey) { _, _ in
            viewModel.reconfigureAutoRefresh()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.snapshot?.displayPlanName ?? "Claude subscription")
                    .font(.headline)
            }

            Spacer()

            sourceBadge
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = viewModel.snapshot {
            VStack(alignment: .leading, spacing: 12) {
                if let currentSession = snapshot.currentSession {
                    LimitSectionCard(section: currentSession)
                }

                if let weeklyLimit = snapshot.weeklyLimit {
                    LimitSectionCard(section: weeklyLimit)
                }

                if appModel.showRawCapture {
                    DisclosureGroup("Raw /usage capture") {
                        ScrollView {
                            Text(snapshot.rawText.isEmpty ? "No raw text captured." : snapshot.rawText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                        .padding(.top, 4)
                    }
                }
            }
        } else if viewModel.isRefreshing {
            ProgressView("Refreshing /usage…")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let message = viewModel.lastErrorMessage {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text("Run a capture to read the current Claude subscription limits.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = viewModel.lastErrorMessage, viewModel.sourceState != .live {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(viewModel.isRefreshing ? "Refreshing…" : "Refresh") {
                    Task {
                        await viewModel.refresh(forceVisibleLoading: true)
                    }
                }
                .disabled(viewModel.isRefreshing)

                Button("Close") {
                    dismiss()
                }

                Button("Quit") {
                    NSApp.terminate(nil)
                }

                Spacer()

                SettingsLink {
                    Text("Settings…")
                }
            }
        }
    }

    private var sourceBadge: some View {
        Text(sourceLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(sourceColor.opacity(0.18))
            )
            .foregroundStyle(sourceColor)
    }

    private var sourceLabel: String {
        switch viewModel.sourceState {
        case .live:
            return "Live"
        case .partial:
            return "Partial"
        case .stale:
            return "Stale"
        case .authRequired:
            return "Auth"
        case .apiKeyMode:
            return "API Key"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var sourceColor: Color {
        switch viewModel.sourceState {
        case .live:
            return .green
        case .partial:
            return .orange
        case .stale:
            return .yellow
        case .authRequired, .apiKeyMode, .unavailable:
            return .red
        }
    }
}

private struct LimitSectionCard: View {
    let section: LimitSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))

            if let metric = section.primaryMetricText {
                Text(metric)
                    .font(.body)
            }

            if let progressPercent = section.progressPercent {
                ProgressView(value: progressPercent, total: 100)
                    .controlSize(.small)
                Text("\(Int(progressPercent))% detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let usedText = section.usedText, usedText != section.primaryMetricText {
                Text(usedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let resetText = section.resetText {
                Text(resetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
