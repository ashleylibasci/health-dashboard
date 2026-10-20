import AppIntents
import HealthKit

/// "Hey Siri, log water in Health Dashboard": one bottle at her size, saved to Apple Health.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a bottle of water"
    static let description = IntentDescription("Saves one bottle of water, at your bottle size, to Apple Health.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = HKHealthStore()
        guard store.authorizationStatus(for: HealthReader.waterType) == .sharingAuthorized else { throw ShortcutError.noHealthPermission }
        var snap = WidgetSnapshot.load()
        let ml = snap.bottleMl ?? 710
        try await store.save(HKQuantitySample(type: HealthReader.waterType, quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml),
                                              start: .now, end: .now))
        let day = WidgetSnapshot.calendarKey()
        snap.waterBottles = (snap.waterDay == day ? snap.waterBottles : 0) + 1
        snap.waterDay = day
        snap.save()
        return .result(dialog: "Logged a bottle. That’s \(snap.waterBottles.formatted(.number.precision(.fractionLength(0...2)))) of \(snap.waterGoal.formatted(.number.precision(.fractionLength(0...2)))) today.")
    }
}

/// "What's my recovery?": today's score and what it means, from the latest numbers the app worked out.
struct RecoveryIntent: AppIntent {
    static let title: LocalizedStringResource = "Today’s recovery"
    static let description = IntentDescription("Tells you today’s recovery score.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int?> {
        let s = WidgetSnapshot.load()
        guard s.isFromToday, let score = s.recovery else {
            return .result(value: nil, dialog: "Today’s recovery isn’t ready yet. Open Health Dashboard once your Watch has synced last night.")
        }
        return .result(value: score, dialog: "Your recovery is \(score), \(s.recoveryLabel.lowercased()). \(s.headline).")
    }
}

/// "Set my smart alarm for 7:45": sets the Watch's smart alarm (the Watch finishes setting it
/// next time its app is open, as watchOS requires).
struct SetSmartAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Set smart alarm"
    static let description = IntentDescription("Sets your Watch to wake you in light sleep, up to 30 minutes before this time.")

    @Parameter(title: "Up by", kind: .time)
    var time: Date

    @Parameter(title: "Every day", default: true)
    var repeats: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Wake me by \(\.$time)") { \.$repeats }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        var plan = AlarmLink.shared.plan ?? SmartAlarmPlan(latest: 0)
        plan.latest = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
        plan.repeats = repeats
        AlarmLink.shared.set(plan)
        return .result(dialog: "Smart alarm set for \(plan.latestText). Open Health Dashboard on your Watch if it hasn’t confirmed by bedtime.")
    }
}

struct TurnOffSmartAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn off smart alarm"
    static let description = IntentDescription("Turns off your Watch’s smart alarm.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AlarmLink.shared.set(nil)
        return .result(dialog: "Smart alarm turned off.")
    }
}

enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case noHealthPermission
    var localizedStringResource: LocalizedStringResource {
        "Open Health Dashboard and allow it to save to Apple Health first."
    }
}

/// The phrases Siri and Spotlight offer without any setup.
struct HealthDashboardShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogLatteIntent(), phrases: ["Log a latte in \(.applicationName)", "Log coffee in \(.applicationName)"],
                    shortTitle: "Log a latte", systemImageName: "cup.and.saucer.fill")
        AppShortcut(intent: LogWaterIntent(), phrases: ["Log water in \(.applicationName)", "Log a bottle in \(.applicationName)"],
                    shortTitle: "Log water", systemImageName: "drop.fill")
        AppShortcut(intent: RecoveryIntent(), phrases: ["What’s my recovery in \(.applicationName)", "\(.applicationName) recovery"],
                    shortTitle: "Recovery", systemImageName: "heart.fill")
        AppShortcut(intent: SetSmartAlarmIntent(), phrases: ["Set my smart alarm in \(.applicationName)", "Set a \(.applicationName) alarm"],
                    shortTitle: "Set smart alarm", systemImageName: "alarm.fill")
        AppShortcut(intent: TurnOffSmartAlarmIntent(), phrases: ["Turn off my smart alarm in \(.applicationName)"],
                    shortTitle: "Alarm off", systemImageName: "alarm")
    }
}
