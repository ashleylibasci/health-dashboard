import Foundation
import UserNotifications
import HealthCore

/// The pill reminders (H-A1), scheduled on the phone from
/// `PillReminderPlan`: a week ahead, replaced whenever she takes a pill,
/// changes a setting or the data refreshes, so a pill she has taken (here
/// or in Apple Health) never gets a reminder.
enum PillReminders {
    static let prefix = "pill-"

    /// Replaces every pending pill reminder with `plan`. Does nothing more
    /// if notifications aren't allowed.
    static func reschedule(_ plan: [PillReminder], pillTime: Minutes, packLength: Int) async {
        await cancelAll()
        guard !plan.isEmpty, await Nudges.isAllowed() else { return }
        let center = UNUserNotificationCenter.current()
        for r in plan {
            let content = content(for: r, pillTime: pillTime, packLength: packLength)
            content.threadIdentifier = "pill"
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let id = prefix + r.kind.rawValue + "-" + String(Int(r.fire.timeIntervalSince1970))
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Clears pill reminders already on screen (she just took it).
    static func clearShown() async {
        let center = UNUserNotificationCenter.current()
        let shown = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: shown)
    }

    /// What each reminder says.
    static func content(for r: PillReminder, pillTime: Minutes, packLength: Int) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        switch r.kind {
        case .newPackTomorrow:
            c.title = "New pack tomorrow"
            c.body = "Pill 1 is tomorrow at \(Clock.format(pillTime)). Have your new pack with you."
        case .onTime where r.isNewPack:
            c.title = "New pack today"
            c.body = "Pill 1 of \(packLength). Starting on time matters most."
        case .onTime:
            c.title = "Pill time"
            c.body = "Pill \(r.packDay) of \(packLength)."
        case .followUp:
            c.title = r.isNewPack ? "New pack: pill 1 not taken yet" : "Pill not taken yet"
            c.body = "Pill \(r.packDay) of \(packLength). Open the app to mark it taken."
        }
        return c
    }
}
