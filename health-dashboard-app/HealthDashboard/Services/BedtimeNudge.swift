import Foundation
import UserNotifications
import HealthCore

/// The bedtime nudge (H-C4, Settings → Sleep & alarm): a gentle
/// notification 45 minutes before tonight's bedtime, "Lights low, screens
/// down". Scheduled for tonight and tomorrow night from `tonightBedtime`
/// and replaced on every refresh. A night that already has a clock-change
/// bedtime reminder doesn't get a second one.
enum BedtimeNudge {
    static let prefix = "bedtime-nudge-"
    static let lead = 45

    /// Tonight's and tomorrow night's nudge times that are still ahead.
    /// `bedtime` is minutes relative to the wake day (`tonightBedtime`).
    static func fireDates(bedtime: Minutes, nextWakeDay: Date, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        (0...1).compactMap { offset in
            guard let wakeDay = calendar.date(byAdding: .day, value: offset, to: nextWakeDay) else { return nil }
            let fire = AppDay.date(bedtime - lead, relativeTo: wakeDay, calendar: calendar)
            return fire > now ? fire : nil
        }
    }

    /// Replaces the pending nudges with ones at `dates`. Doesn't ask for
    /// permission; does nothing if notifications aren't allowed.
    static func reschedule(_ dates: [Date], bedtime: Minutes) async {
        await cancel()
        guard await Nudges.isAllowed() else { return }
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        // Evenings that already have a clock-change reminder.
        let reminded = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(BedtimeReminders.prefix) }
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            .map { AppDay.day(containing: $0, calendar: cal) }
        for fire in dates where !reminded.contains(where: { cal.isDate($0, inSameDayAs: AppDay.day(containing: fire, calendar: cal)) }) {
            let content = UNMutableNotificationContent()
            content.title = "Lights low, screens down"
            content.body = "Bed by \(Clock.format(bedtime)). Dim lights and put your phone away to help you fall asleep."
            content.sound = .default
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + String(Int(fire.timeIntervalSince1970)),
                                                        content: content, trigger: trigger))
        }
    }

    static func cancel() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

extension AppModel {
    /// Schedules (or cancels) the bedtime nudge from tonight's bedtime.
    /// Only from her own nights: an example bedtime isn't hers.
    func updateBedtimeNudge() async {
        guard store.data.sleepExtras.bedtimeNudge, !usingSampleData else { await BedtimeNudge.cancel(); return }
        let bedtime = tonightBedtime
        await BedtimeNudge.reschedule(BedtimeNudge.fireDates(bedtime: bedtime, nextWakeDay: nextWakeDay), bedtime: bedtime)
    }
}
