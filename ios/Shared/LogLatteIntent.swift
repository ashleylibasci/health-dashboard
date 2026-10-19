import AppIntents
import HealthKit

/// Logs a 130 mg latte to Apple Health from the widget, without opening the app.
struct LogLatteIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a latte"
    static let description = IntentDescription("Saves a 130 mg latte to Apple Health.")

    func perform() async throws -> some IntentResult {
        let store = HKHealthStore()
        let type = HKQuantityType(.dietaryCaffeine)
        // Without permission the save would fail silently; say why instead.
        guard store.authorizationStatus(for: type) == .sharingAuthorized else {
            throw LatteError.noPermission
        }
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: 130), start: .now, end: .now,
                                      metadata: [HKMetadataKeyFoodType: "Latte"])
        try await store.save(sample)
        var snap = WidgetSnapshot.load()
        let tonight = WidgetSnapshot.eveningKey()
        snap.caffeineMg = (snap.caffeineDay == tonight ? snap.caffeineMg : 0) + 130
        snap.caffeineDay = tonight
        snap.save()
        return .result()
    }
}

enum LatteError: Error, CustomLocalizedStringResourceConvertible {
    case noPermission
    var localizedStringResource: LocalizedStringResource {
        "Open Health Dashboard and allow it to save caffeine to Apple Health first."
    }
}
