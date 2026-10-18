import SwiftUI

@main
struct HealthDashboardApp: App {
    @State private var model: AppModel

    init() {
        WatchSync.shared.activate()
        let model = AppModel()
        _model = State(initialValue: model)
        // Background wake-ups from Health start the app here, so observers must be set up at launch.
        BackgroundHealth.shared.start(model)
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
        }
    }
}
