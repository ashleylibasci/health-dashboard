#if os(iOS)
import AppIntents
import Foundation
import HealthKit
import UserNotifications
import HealthCore

/// Taps on widget buttons (a bottle of water, today's pill, a stress
/// rating), kept in the App Group until the app adds them to its log, as
/// `PendingDrinks` does for lattes.
enum PendingLogs {
    struct Entry: Codable {
        enum Kind: Codable {
            /// `savedToHealth`: already saved to Apple Health under the entry's id.
            case water(ml: Double, savedToHealth: Bool)
            case pill
            /// 1 (very calm) – 5 (very stressed).
            case stress(Int)
            /// The smart alarm switched on or off.
            case smartAlarm(Bool)
        }
        var id: UUID
        var date: Date
        var kind: Kind
    }

    private static let key = "next.pendingLogs.v1"

    /// Set by the app: when the intent runs inside the app's own process,
    /// the tap goes straight into the log.
    @MainActor static var onAdded: (() -> Void)?

    static func add(_ entry: Entry) {
        save(load() + [entry])
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

/// "Log a bottle of water": one bottle of her size, saved to Apple Health,
/// from the Caffeine & water widget, Siri or Shortcuts.
struct LogBottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a bottle of water"
    static let description = IntentDescription("Logs one bottle of water now and saves it to Apple Health.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard var snapshot = WidgetSnapshot.load(), snapshot.bottleML > 0 else {
            return .result(dialog: "Open Health Dashboard once first, so it knows your bottle size.")
        }
        let now = Date()
        let id = UUID()
        let ml = snapshot.bottleML
        let saved = await Self.saveToHealth(ml: ml, at: now, id: id)
        PendingLogs.add(.init(id: id, date: now, kind: .water(ml: ml, savedToHealth: saved)))
        // The widgets count it straight away; the app recounts when it opens.
        if !snapshot.isCurrent(at: now) {
            snapshot.caffeineMg = 0
            snapshot.waterML = 0
            snapshot.appDayStart = Calendar.current.startOfDay(for: now)
        }
        snapshot.waterML += ml
        snapshot.save()
        await MainActor.run { PendingLogs.onAdded?() }
        return .result(dialog: "Logged a bottle, \(Int((ml / 29.5735).rounded())) oz.")
    }

    /// Saved with the entry's id, as the app does, so the app can edit or
    /// delete it later. False when Health isn't available or allowed; the
    /// app saves it when it next opens.
    private static func saveToHealth(ml: Double, at date: Date, id: UUID) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let store = HKHealthStore()
        let type = HKQuantityType(.dietaryWater)
        guard store.authorizationStatus(for: type) == .sharingAuthorized else { return false }
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml),
                                      start: date, end: date, metadata: [HKMetadataKeyExternalUUID: id.uuidString])
        do { try await store.save(sample); return true } catch { return false }
    }
}

/// "Taken" for today's pill (H-A1), from the Cycle widget. Today's pill
/// reminders that haven't gone off yet are cancelled here, so a pill taken
/// from the widget never gets one even before the app opens.
struct PillTakenIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark today's pill taken"
    static let description = IntentDescription("Marks today's pill as taken and stops today's reminder.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        guard var snapshot = WidgetSnapshot.load(), var pill = snapshot.pill(at: now) else {
            return .result(dialog: "Open Health Dashboard once first, so it knows your pack.")
        }
        guard pill.isPillDay else { return .result(dialog: "No pill today.") }
        guard pill.taken == nil else { return .result(dialog: "Already marked taken.") }
        PendingLogs.add(.init(id: UUID(), date: now, kind: .pill))
        pill.taken = now
        snapshot.pill = pill
        snapshot.save()
        await Self.cancelReminders(around: pill.pillTime)
        await MainActor.run { PendingLogs.onAdded?() }
        return .result(dialog: "Marked taken.")
    }

    /// Today's on-time reminder and its repeats (`PillReminders` ids end in
    /// their fire time), and any already on screen. The app reschedules
    /// the rest when it next runs.
    private static func cancelReminders(around pillTime: Date) async {
        let center = UNUserNotificationCenter.current()
        let today = pillTime.addingTimeInterval(-3600)...pillTime.addingTimeInterval(3 * 3600)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { id in
            guard id.hasPrefix("pill-onTime-") || id.hasPrefix("pill-followUp-"),
                  let seconds = id.split(separator: "-").last.flatMap({ Double($0) }) else { return false }
            return today.contains(Date(timeIntervalSince1970: seconds))
        }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let shown = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("pill-") }
        center.removeDeliveredNotifications(withIdentifiers: shown)
    }
}

/// A 1–5 stress tap, from the Stress widget.
struct LogStressIntent: AppIntent {
    static let title: LocalizedStringResource = "Log how stressed you feel"
    static let description = IntentDescription("Logs how stressed you feel right now, from 1 (very calm) to 5 (very stressed).")

    @Parameter(title: "Stress", description: "1 (very calm) to 5 (very stressed)", inclusiveRange: (1, 5))
    var level: Int

    init() {}

    init(level: Int) {
        self.level = level
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let level = min(max(level, 1), 5)
        PendingLogs.add(.init(id: UUID(), date: now, kind: .stress(level)))
        if var snapshot = WidgetSnapshot.load() {
            snapshot.stress = .init(level: level, date: now)
            snapshot.save()
        }
        await MainActor.run { PendingLogs.onAdded?() }
        return .result(dialog: "Logged stress \(level).")
    }
}

/// The smart alarm on or off, from its Control Center switch (iOS 18).
/// On, the Watch still needs its app opened before bed to turn the alarm on.
struct SetSmartAlarmIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Smart alarm"
    static let description = IntentDescription("Turns the smart alarm on your Watch on or off.")

    @Parameter(title: "Smart alarm on")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        PendingLogs.add(.init(id: UUID(), date: .now, kind: .smartAlarm(value)))
        if var snapshot = WidgetSnapshot.load() {
            snapshot.smartAlarmOn = value
            snapshot.save()
        }
        await MainActor.run { PendingLogs.onAdded?() }
        return .result()
    }
}
#endif
