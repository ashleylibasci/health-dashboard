import ActivityKit
import Foundation
import WatchConnectivity
import HealthCore

/// Starts, updates and ends the bedtime Live Activity (D-W1). It runs from
/// an hour before tonight's bedtime until 2am (half an hour after a later
/// bedtime). iOS only lets the app start one while it's open, so on iOS 26
/// and later it's scheduled ahead for its start time (with a gentle alert as
/// it appears); on earlier versions it starts when she opens the app in that
/// hour. Live Activities can be switched off for the app in iOS Settings.
@MainActor
enum BedtimeActivities {
    typealias Attributes = BedtimeActivityAttributes

    /// It appears an hour before bed.
    static let lead: TimeInterval = 3600

    /// 2am after `bed`, or half an hour after a bedtime later than that.
    static func end(for bed: Date, calendar: Calendar = .current) -> Date {
        let twoAM = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: bed) ?? bed
        let next = twoAM > bed ? twoAM : calendar.date(byAdding: .day, value: 1, to: twoAM) ?? bed
        return max(next, bed.addingTimeInterval(30 * 60))
    }

    /// Brings the activities in line with `state` (nil: none wanted). One
    /// for the evening is updated in place, even if the bedtime moved; one
    /// that's over, or for another evening, ends.
    static func update(_ state: Attributes.ContentState?, now: Date = .now) async {
        let all = Activity<Attributes>.activities
        let tonight = all.first { a in
            guard let state else { return false }
            return abs(a.attributes.night.timeIntervalSince(state.bedtime)) < 6 * 3600 && now < end(for: state.bedtime)
        }
        for a in all where a.id != tonight?.id {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        guard let state else { return }
        let finish = end(for: state.bedtime)
        let content = ActivityContent(state: state, staleDate: finish)
        if let tonight {
            if tonight.content.state != state { await tonight.update(content) }
            return
        }
        guard now < finish, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let start = state.bedtime.addingTimeInterval(-lead)
        let attributes = Attributes(night: state.bedtime)
        // `-demoBedtimeActivity`: straight away, whatever the time.
        if now >= start || DemoMode.bedtimeActivity != nil {
            _ = try? Activity.request(attributes: attributes, content: content)
        } else if #available(iOS 26.0, *) {
            let alert = AlertConfiguration(title: "Bed in an hour",
                                           body: "Bed by \(time(state.bedtime)) \u{00B7} up \(time(state.upAt))",
                                           sound: .default)
            _ = try? Activity.request(attributes: attributes, content: content, style: .standard,
                                      alertConfiguration: alert, start: start)
        }
    }

    private static func time(_ date: Date) -> String { Clock.format(Clock.minutesOfDay(date)) }
}

extension AppModel {
    /// What tonight's bedtime Live Activity shows: the one bedtime, the
    /// same up time as Today's Tonight card, and the Watch alarm. nil on
    /// example data (an example bedtime isn't hers) and before onboarding.
    var bedtimeActivityState: BedtimeActivityAttributes.ContentState? {
        guard store.data.onboarded, !usingSampleData || DemoMode.bedtimeActivity != nil else { return nil }
        let tonight = tonightPlan
        return .init(bedtime: AppDay.date(tonightBedtime, relativeTo: nextWakeDay),
                     upAt: AppDay.date(tonight.wake ?? tonight.upBy, relativeTo: nextWakeDay),
                     alarm: watchAlarmTonight)
    }

    /// The smart alarm for tomorrow morning, as the activity (and the
    /// bedtime nudge's button, D-N2) shows it.
    var watchAlarmTonight: BedtimeActivityAttributes.WatchAlarm {
        if let demo = DemoMode.bedtimeActivity, let alarm = BedtimeActivityAttributes.WatchAlarm(rawValue: demo) { return alarm }
        guard WCSession.isSupported(), WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return .hidden }
        // Weekdays only, before a weekend morning: no alarm to talk about.
        if store.data.alarmWeekdaysOnly, activeAlarmOverride == nil, Calendar.current.isDateInWeekend(nextWakeDay) { return .hidden }
        guard store.data.smartAlarmEnabled else { return .off }
        return watchAlarmIsOn ? .on : .openWatch
    }

    func updateBedtimeActivity() {
        let state = bedtimeActivityState
        Task { await BedtimeActivities.update(state) }
    }
}
