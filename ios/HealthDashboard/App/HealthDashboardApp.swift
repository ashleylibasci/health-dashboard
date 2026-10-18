import SwiftUI

@main
struct HealthDashboardApp: App {
    @State private var model = AppModel()

    init() { WatchSync.shared.activate() }

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
        }
    }
}
