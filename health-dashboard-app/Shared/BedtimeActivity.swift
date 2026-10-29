#if os(iOS)
import ActivityKit
import AppIntents
import Foundation

/// The bedtime Live Activity (D-W1): from an hour before tonight's bedtime,
/// "Bed in 45 min · up 8:30am · Watch alarm on" on the Lock Screen and in the
/// Dynamic Island. Started and updated by the app (`BedtimeActivities`),
/// drawn by the widget extension.
struct BedtimeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Tonight's bedtime (`tonightBedtime`) and her up time, as dates.
        var bedtime: Date
        var upAt: Date
        var alarm: WatchAlarm
    }

    /// The Watch's smart alarm for the morning after.
    enum WatchAlarm: String, Codable, Hashable {
        /// The Watch says it's on for that morning.
        case on
        /// On in the app; the Watch app still needs opening before bed.
        case openWatch
        /// Off: the activity offers "Turn on Watch alarm".
        case off
        /// No Watch, or no alarm tomorrow (weekdays only, before a weekend
        /// morning): nothing about an alarm.
        case hidden
    }

    /// The evening it's for (tonight's bedtime when it started): a moved
    /// bedtime updates it, another evening's ends.
    var night: Date
}

/// "Turn on Watch alarm" on the bedtime Live Activity: turns the smart alarm
/// on in the app and sends tonight's window to the Watch. It runs in the
/// app (a Live Activity intent), which updates the activity; the Watch app
/// still has to be opened once before bed, and the activity then says so.
struct TurnOnWatchAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn on Watch alarm"
    static let description = IntentDescription("Turns on the smart alarm on your Watch for tomorrow morning.")

    init() {}

    func perform() async throws -> some IntentResult {
        PendingLogs.add(.init(id: UUID(), date: .now, kind: .smartAlarm(true)))
        if var snapshot = WidgetSnapshot.load() {
            snapshot.smartAlarmOn = true
            snapshot.save()
        }
        await MainActor.run { PendingLogs.onAdded?() }
        // Straight away, even before the app has worked out the window.
        for activity in Activity<BedtimeActivityAttributes>.activities where activity.content.state.alarm == .off {
            var state = activity.content.state
            state.alarm = .openWatch
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
        return .result()
    }
}
#endif
