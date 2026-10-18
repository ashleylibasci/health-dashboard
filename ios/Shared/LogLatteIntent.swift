import AppIntents
import HealthKit

/// Logs a 130 mg latte to Apple Health from the widget, without opening the app.
struct LogLatteIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a latte"
    static let description = IntentDescription("Saves a 130 mg latte to Apple Health.")

    func perform() async throws -> some IntentResult {
        let store = HKHealthStore()
        let type = HKQuantityType(.dietaryCaffeine)
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: 130), start: .now, end: .now)
        try await store.save(sample)
        var snap = WidgetSnapshot.load()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: .now)
        snap.caffeineMg = (snap.caffeineDay == today ? snap.caffeineMg : 0) + 130
        snap.caffeineDay = today
        snap.save()
        return .result()
    }
}
