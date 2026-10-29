import Foundation
import HealthCore

/// Bleeding, symptoms and her method saved to Apple Health (G3).
extension AppModel {
    /// Turning it on asks Health for permission to save, then saves
    /// everything logged so far. Never on example data.
    func setSavesCycleToHealth(_ on: Bool) async {
        guard on else {
            store.data.savesCycleToHealth = false
            return
        }
        guard !DemoMode.isOn else {
            store.data.savesCycleToHealth = true
            return
        }
        _ = await CycleHealthWrite.requestAccess(health.store)
        store.data.savesCycleToHealth = true
    }

    /// Saves what's new and removes what she deleted. One at a time; a
    /// change while one runs runs it again after.
    func syncCycleToHealth() async {
        guard store.data.savesCycleToHealth, !DemoMode.isOn else { return }
        guard !Self.cycleSyncRunning else { Self.cycleSyncAgain = true; return }
        Self.cycleSyncRunning = true
        repeat {
            Self.cycleSyncAgain = false
            if let saved = await CycleHealthWrite.sync(health.store, data: store.data, method: store.birthControl),
               saved != store.data.cycleHealthSaved {
                store.data.cycleHealthSaved = saved
            }
        } while Self.cycleSyncAgain
        Self.cycleSyncRunning = false
    }

    private static var cycleSyncRunning = false
    private static var cycleSyncAgain = false
}
