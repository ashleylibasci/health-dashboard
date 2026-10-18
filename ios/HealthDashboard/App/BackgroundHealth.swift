import HealthKit

/// Keeps the numbers fresh without opening the app: Apple Health wakes the app when new data
/// arrives (a night of sleep from the Watch, a morning heart reading, a latte logged anywhere),
/// and the app re-reads Health and pushes today's summary to the widgets and the Watch.
/// iOS decides exactly when to wake the app, usually within minutes to an hour.
@MainActor
final class BackgroundHealth {
    static let shared = BackgroundHealth()

    private weak var model: AppModel?
    private var started = false
    private var running: Task<Void, Never>?
    private var lastRefresh = Date.distantPast

    /// What to watch, and how soon to be woken. Logs (drinks, water, period) come in right away;
    /// slow-moving readings at most hourly to save battery.
    private static var watched: [(HKSampleType, HKUpdateFrequency)] {
        [
            (HealthReader.sleepType, .immediate),
            (HealthReader.caffeineType, .immediate),
            (HealthReader.waterType, .immediate),
            (HealthReader.alcoholType, .immediate),
            (HealthReader.menstrualFlowType, .immediate),
            (HealthReader.restingHrType, .hourly),
            (HealthReader.hrvType, .hourly),
            (HealthReader.wristTempType, .hourly),
        ]
    }

    /// Call at launch (background wake-ups start the app fresh) and again right after Health is connected.
    func start(_ model: AppModel) {
        self.model = model
        guard !started, HealthReader.isAvailable, model.isHealthConnected, !model.isDemoMode else { return }
        started = true
        for (type, frequency) in Self.watched {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    await BackgroundHealth.shared.update()
                    // Tells Health the update was handled; without it, Health backs off waking the app.
                    completion()
                }
            }
            HealthReader.store.execute(query)
            HealthReader.store.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
        }
    }

    /// One refresh at a time; several types arriving together share it.
    func update() async {
        if let running {
            await running.value
            return
        }
        // Every observer fires once when it starts; skip if the app just refreshed.
        guard Date.now.timeIntervalSince(lastRefresh) > 120, let model else { return }
        let task = Task { @MainActor in
            await model.refreshHealth(quiet: true)
            if model.healthState == .ready { model.publishWidgetSnapshot() }
            self.lastRefresh = .now
        }
        running = task
        await task.value
        running = nil
    }

    /// Called after the app refreshes on its own (opening it), so observers don't repeat the work.
    func noteRefreshed() { lastRefresh = .now }
}
