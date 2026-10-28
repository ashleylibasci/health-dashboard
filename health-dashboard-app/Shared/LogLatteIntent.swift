import AppIntents
import Foundation
import HealthKit

/// Lattes logged outside the app (Siri, Shortcuts, the widget button), kept
/// in the App Group until the app adds them to today's log.
enum PendingDrinks {
    struct Entry: Codable {
        var entryID: UUID
        var drinkID: UUID
        var name: String
        var mg: Int
        var date: Date
        /// Already saved to Apple Health under `entryID`.
        var savedToHealth: Bool
    }

    private static let key = "next.pendingDrinks.v1"

    /// Set by the app: when the intent runs inside the app's own process, the
    /// drink goes straight into the log.
    @MainActor static var onAdded: (() -> Void)?

    static func add(_ entry: Entry) {
        var all = load()
        all.append(entry)
        save(all)
    }

    static func takeAll() -> [Entry] {
        let all = load()
        if !all.isEmpty { save([]) }
        return all
    }

    private static func load() -> [Entry] {
        guard let data = WidgetSnapshot.defaults?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func save(_ all: [Entry]) {
        WidgetSnapshot.defaults?.set(try? JSONEncoder().encode(all), forKey: key)
    }
}

/// "Log a latte in Health Next": logs her saved latte (or her first saved
/// drink) now, saves it to Apple Health, and updates the widgets. Works from
/// Siri, Shortcuts, Spotlight and the Caffeine & water widget.
struct LogLatteIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a latte"
    static let description = IntentDescription("Logs your usual latte now and saves the caffeine to Apple Health.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard var snapshot = WidgetSnapshot.load(), let drink = snapshot.quickDrink else {
            return .result(dialog: "Open Health Next once first, so it knows your drinks.")
        }
        let now = Date()
        let entryID = UUID()
        let saved = await Self.saveToHealth(mg: drink.mg, at: now, id: entryID)
        PendingDrinks.add(.init(entryID: entryID, drinkID: drink.id, name: drink.name, mg: drink.mg,
                                date: now, savedToHealth: saved))
        // The widgets count it straight away; the app recounts when it opens.
        if !snapshot.isCurrent(at: now) {
            snapshot.caffeineMg = 0
            snapshot.waterML = 0
            snapshot.appDayStart = Calendar.current.startOfDay(for: now)
        }
        snapshot.caffeineMg += drink.mg
        snapshot.save()
        await MainActor.run { PendingDrinks.onAdded?() }
        return .result(dialog: "Logged a \(drink.name.lowercased()), \(drink.mg) mg.")
    }

    /// Saves it with the entry's id (as the app does), so the app can edit or
    /// delete it later. False when Health isn't available or allowed; the app
    /// saves it when it next opens.
    private static func saveToHealth(mg: Int, at date: Date, id: UUID) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let store = HKHealthStore()
        let type = HKQuantityType(.dietaryCaffeine)
        guard store.authorizationStatus(for: type) == .sharingAuthorized else { return false }
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: Double(mg)),
                                      start: date, end: date, metadata: [HKMetadataKeyExternalUUID: id.uuidString])
        do { try await store.save(sample); return true } catch { return false }
    }
}
