import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Bindable var appModel: AppModel
    let viewModel: LimitViewModel
    var recentSamples: [UsageHistorySample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
            footer
        }
        .frame(width: 390)
        .padding(16)
        .onChange(of: appModel.refreshSettingsKey) { _, _ in
            viewModel.reconfigureAutoRefresh()
        }
    }

    // MARK: - Header (fix: center alignment, badges grouped)

    private var header: some View {
        HStack {
            Text(viewModel.claudeSnapshot?.displayPlanName ?? "Claude subscription")
                .font(.headline)

            Spacer()

            HStack(spacing: 6) {
                // Data source badge
                if let snapshot = viewModel.claudeSnapshot {
                    Text(snapshot.dataSource == .claudeAPI ? "API" : "PTY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        .foregroundStyle(.secondary)
                }

                sourceBadge
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let snapshot = viewModel.claudeSnapshot {
            VStack(alignment: .leading, spacing: 12) {
                if let accountLabel = snapshot.accountLabel {
                    Text(accountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let currentSession = snapshot.currentSession {
                    LimitSectionCard(
                        section: currentSession,
                        resetsAt: viewModel.sessionResetsAt,
                        warnThreshold: appModel.warnThreshold,
                        dangerThreshold: appModel.dangerThreshold
                    )
                }

                if let weeklyLimit = snapshot.weeklyLimit {
                    LimitSectionCard(
                        section: weeklyLimit,
                        resetsAt: viewModel.weeklyResetsAt,
                        warnThreshold: appModel.warnThreshold,
                        dangerThreshold: appModel.dangerThreshold
                    )
                }

                // Per-model breakdown
                PerModelBreakdownView(
                    models: snapshot.perModelLimits,
                    warnThreshold: appModel.warnThreshold,
                    dangerThreshold: appModel.dangerThreshold
                )

                // Extra usage
                if let extra = snapshot.extraUsage, extra.isEnabled {
                    extraUsageCard(extra)
                }

                if appModel.showRawCapture, !snapshot.rawText.isEmpty {
                    DisclosureGroup("Raw capture") {
                        ScrollView {
                            Text(snapshot.rawText)
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
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading usage data…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            emptyStateView
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.open.with.lines.needle.33percent")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 6) {
                Text("No usage data yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if viewModel.claudeLastErrorMessage != nil {
                    Text("Could not load data. Connect to Claude.ai API or check that Claude CLI is installed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Connect to Claude.ai API in Settings or install Claude CLI to get started.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Button("Open Settings") {
                openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Mini chart (expandable)
            if recentSamples.count >= 2 {
                DisclosureGroup("Usage trend (24h)") {
                    MiniChartView(samples: recentSamples)
                        .padding(.top, 4)
                }
            }

            // Error hint
            if let hint = viewModel.claudeLastHint, viewModel.claudeSourceState != .live {
                Text(hint)
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

                Button("Dashboard") {
                    openWindow(id: "dashboard")
                }

                Button("Close") {
                    dismiss()
                }

                Button("Quit") {
                    NSApp.terminate(nil)
                }

                Spacer()

                Button("Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func extraUsageCard(_ extra: ExtraUsageInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Extra Usage")
                .font(.subheadline.weight(.semibold))

            if let utilization = extra.utilization {
                ProgressView(value: min(max(utilization, 0), 100), total: 100)
                    .tint(progressColor(for: utilization))
                    .controlSize(.small)
                Text("\(Int(utilization))% of extra limit used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let used = extra.usedCents, let limit = extra.limitCents {
                Text("\(formatCents(used, currency: extra.currency)) / \(formatCents(limit, currency: extra.currency))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let balance = extra.balanceCents {
                Text("Prepaid: \(formatCents(balance, currency: extra.currency))")
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

    private func formatCents(_ cents: Int, currency: String) -> String {
        let amount = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
    }

    private func progressColor(for value: Double) -> Color {
        if value >= Double(appModel.dangerThreshold) { return .red }
        if value >= Double(appModel.warnThreshold) { return .orange }
        return .green
    }

    private var sourceBadge: some View {
        let state = viewModel.claudeSourceState
        return Text(sourceLabel(for: state))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(sourceColor(for: state).opacity(0.18))
            )
            .foregroundStyle(sourceColor(for: state))
    }

    private func sourceLabel(for state: CaptureSourceState) -> String {
        switch state {
        case .live: return "Live"
        case .partial: return "Partial"
        case .stale: return "Stale"
        case .authRequired: return "Auth"
        case .apiKeyMode: return "API Key"
        case .unavailable: return "Unavailable"
        }
    }

    private func sourceColor(for state: CaptureSourceState) -> Color {
        switch state {
        case .live: return .green
        case .partial: return .orange
        case .stale: return .yellow
        case .authRequired, .apiKeyMode, .unavailable: return .red
        }
    }
}

// MARK: - LimitSectionCard (fixed: no duplication)

private struct LimitSectionCard: View {
    let section: LimitSection
    let resetsAt: Date?
    let warnThreshold: Int
    let dangerThreshold: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))

                if let progressPercent = section.progressPercent {
                    HStack(spacing: 8) {
                        ProgressView(value: progressPercent, total: 100)
                            .tint(progressColor(for: progressPercent))
                            .controlSize(.small)
                        Text("\(Int(progressPercent))%")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }

            Spacer()

            // Countdown timer
            if let windowMinutes = section.windowDurationMinutes {
                CountdownTimerView(
                    resetsAt: resetsAt ?? section.resetsAt,
                    windowDurationMinutes: windowMinutes,
                    warnThreshold: warnThreshold,
                    dangerThreshold: dangerThreshold
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func progressColor(for value: Double) -> Color {
        if value >= Double(dangerThreshold) { return .red }
        if value >= Double(warnThreshold) { return .orange }
        return .green
    }
}
