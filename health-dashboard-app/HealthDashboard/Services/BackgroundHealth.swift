import Foundation
import HealthKit
import UIKit

/// Keeps the numbers fresh without opening the app: Apple Health wakes the
/// app when new data arrives (last night's sleep from the Watch, a morning
/// heart reading, a latte or water logged anywhere), and the app re-reads
/// Health, which also updates the Watch. iOS decides exactly when to wake the
/// app, usually within minutes to an hour. Health can't be read while the
/// phone is locked, so some updates wait until it's next unlocked; the last
/// numbers stay on screen until then.
@MainActor
final class BackgroundHealth {
    static let shared = BackgroundHealth()

    private weak var model: AppModel?
    private var started = false
    private var running: Task<Void, Never>?
    /// New data arrived while a refresh was running: run once more after it.
    private var needsAnotherPass = false
    /// Seconds between refreshes started by new Health data.
    private static let minimumGap: TimeInterval = 30

    /// Logs (drinks, water, periods) and sleep come in right away; slow-moving
    /// readings at most hourly, to save battery.
    private static let watched: [(HKSampleType, HKUpdateFrequency)] = [
        (HKCategoryType(.sleepAnalysis), .immediate),
        (HKQuantityType(.dietaryCaffeine), .immediate),
        (HKQuantityType(.dietaryWater), .immediate),
        (HKCategoryType(.menstrualFlow), .immediate),
        (HKQuantityType(.restingHeartRate), .hourly),
        (HKQuantityType(.heartRateVariabilitySDNN), .hourly),
        (HKQuantityType(.appleSleepingWristTemperature), .hourly),
    ]

    /// Call at launch (a background wake-up starts the app fresh) and again
    /// right after Apple Health is connected. Does nothing on example data.
    func start(_ model: AppModel) {
        self.model = model
        guard !started, HealthKitService.isAvailable, !DemoMode.isOn,
              model.store.data.onboarded, !model.prefersSampleData else { return }
        started = true
        let store = model.health.store
        for (type, frequency) in Self.watched {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    await BackgroundHealth.shared.update()
                    // Tells Health the update was handled; without it, Health
                    // backs off waking the app.
                    completion()
                }
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
        }
    }

    /// One refresh at a time. Data that lands mid-refresh triggers exactly one
    /// more pass, so nothing is skipped and types arriving together share it.
    func update() async {
        if let running {
            needsAnotherPass = true
            await running.value
            return
        }
        guard let model, !model.prefersSampleData else { return }
        let task = Task { @MainActor in
            // At most one refresh every 30 seconds: at launch every watched
            // type reports in, and the Watch sends readings while she's using
            // the app, and back-to-back refreshes made scrolling stutter.
            // Whatever arrives meanwhile is read by the next one. Only while
            // she's in the app: a background wake-up has seconds, not 30.
            if UIApplication.shared.applicationState == .active, let last = model.lastRefreshed {
                let wait = Self.minimumGap - Date.now.timeIntervalSince(last)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            }
            repeat {
                needsAnotherPass = false
                // A locked phone throws; the last numbers stay until next time.
                try? await model.refresh()
            } while needsAnotherPass
        }
        running = task
        await task.value
        running = nil
    }
}
