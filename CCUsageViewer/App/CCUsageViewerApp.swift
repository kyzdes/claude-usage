import SwiftUI

@MainActor
@main
struct CCUsageViewerApp: App {
    @State private var appModel: AppModel
    @State private var limitViewModel: LimitViewModel

    init() {
        let appModel = AppModel()
        let limitViewModel = LimitViewModel(appModel: appModel)
        limitViewModel.startIfNeeded()
        _appModel = State(initialValue: appModel)
        _limitViewModel = State(initialValue: limitViewModel)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appModel: appModel, viewModel: limitViewModel)
        } label: {
            Label(limitViewModel.menuBarTitle, systemImage: limitViewModel.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appModel: appModel, viewModel: limitViewModel)
            .frame(width: 480)
        }
    }
}
