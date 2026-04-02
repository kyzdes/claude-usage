import SwiftUI
import SwiftData

@MainActor
@main
struct CCUsageViewerApp: App {
    @State private var appModel: AppModel
    @State private var limitViewModel: LimitViewModel
    @State private var dashboardViewModel: DashboardViewModel
    @State private var authService: WebAuthService
    @State private var recentSamples: [UsageHistorySample] = []

    init() {
        let appModel = AppModel()
        let limitViewModel = LimitViewModel(appModel: appModel)
        let authService = WebAuthService()

        // Initialize history store
        let historyStore = try? UsageHistoryStore()
        limitViewModel.historyStore = historyStore

        let dashVM: DashboardViewModel
        if let store = historyStore {
            dashVM = DashboardViewModel(historyStore: store)
        } else {
            // Use a fallback in-memory store if SwiftData fails
            let fallback = try! UsageHistoryStore()
            limitViewModel.historyStore = fallback
            dashVM = DashboardViewModel(historyStore: fallback)
        }

        limitViewModel.startIfNeeded()

        _appModel = State(initialValue: appModel)
        _limitViewModel = State(initialValue: limitViewModel)
        _dashboardViewModel = State(initialValue: dashVM)
        _authService = State(initialValue: authService)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                appModel: appModel,
                viewModel: limitViewModel,
                recentSamples: recentSamples
            )
            .onAppear {
                loadRecentSamples()
            }
        } label: {
            if appModel.compactMenuBarMode {
                Text(limitViewModel.compactMenuBarTitle)
            } else {
                Label(limitViewModel.menuBarTitle, systemImage: limitViewModel.menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.window)

        Window("Usage Dashboard", id: "dashboard") {
            DashboardView(viewModel: dashboardViewModel, appModel: appModel)
        }
        .defaultSize(width: 700, height: 500)

        Window("CC Usage Viewer Settings", id: "settings") {
            SettingsView(
                appModel: appModel,
                viewModel: limitViewModel,
                authService: authService
            )
            .frame(width: 520, height: 620)
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .defaultSize(width: 520, height: 620)
        .windowResizability(.contentSize)
    }

    private func loadRecentSamples() {
        guard let store = limitViewModel.historyStore else { return }
        let oneDayAgo = Date().addingTimeInterval(-24 * 3600)
        recentSamples = store.samples(from: oneDayAgo)
    }
}
