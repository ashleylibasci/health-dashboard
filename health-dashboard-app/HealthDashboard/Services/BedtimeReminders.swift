import Foundation
import UserNotifications
import HealthCore

/// Local "wind down for bed" reminders for the clock-change plan.
/// Only notifications: nothing here touches alarms, the Watch, or the saved
/// bedtime and wake time.
enum BedtimeReminders {
    static let prefix = "timechange-"

    struct Reminder: Hashable {
        var identifier: String
        /// Wall-clock time to fire (so it follows the clock change on its own).
        var fire: DateComponents
        var title: String
        var body: String
    }

    /// One reminder per plan night, 30 minutes before that night's bedtime.
    /// `nightDate(offset)` gives the evening's calendar date; bedtimes are
    /// minutes relative to the following (wake) day, as everywhere in the app.
    static func timeChangeReminders(nights: [TimeChangePlanner.Night], nightDate: (Int) -> Date,
                                    now: Date = .now, calendar: Calendar = .current) -> [Reminder] {
        nights.compactMap { n in
            let evening = calendar.startOfDay(for: nightDate(n.dayOffset))
            guard let wakeDay = calendar.date(byAdding: .day, value: 1, to: evening) else { return nil }
            let fire = wallClock(n.bedtime - 30, relativeTo: wakeDay, calendar: calendar)
            guard let when = calendar.date(from: fire), when > now else { return nil }
            let body: String
            switch n.dayOffset {
            case ..<0: body = "Wind down for bed. The clocks go back early on Sunday morning."
            case 0: body = "Wind down for bed. The clocks go back tonight at 2am."
            default: body = "Wind down for bed. Your body is still getting used to the new clock."
            }
            return Reminder(identifier: "\(prefix)\(n.dayOffset)", fire: fire,
                            title: "Bed at \(Clock.format(n.bedtime))", body: body)
        }
    }

    /// Asks for notification permission, clears any earlier clock-change
    /// reminders and schedules these. Returns false if permission was refused.
    static func schedule(_ reminders: [Reminder]) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard allowed else { return false }
        await cancelAll()
        for r in reminders {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: r.fire, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: r.identifier, content: content, trigger: trigger))
        }
        return true
    }

    /// Removes every pending clock-change reminder.
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Year/month/day/hour/minute on the wall clock for `minutes` relative to
    /// midnight of `wakeDay` (negative = the evening before).
    static func wallClock(_ minutes: Minutes, relativeTo wakeDay: Date, calendar: Calendar) -> DateComponents {
        let dayShift = Int((Double(minutes) / 1440).rounded(.down))
        let m = minutes - dayShift * 1440
        let day = calendar.date(byAdding: .day, value: dayShift, to: calendar.startOfDay(for: wakeDay)) ?? wakeDay
        var c = calendar.dateComponents([.year, .month, .day], from: day)
        c.hour = m / 60
        c.minute = m % 60
        return c
    }
}
