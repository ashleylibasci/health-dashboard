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
        await registerCategory()
        let hidden = await PrivateNotice.bodyHiddenWhenLocked()
        let center = UNUserNotificationCenter.current()
        for r in plan {
            let content = content(for: r, pillTime: pillTime, packLength: packLength, bodyHiddenWhenLocked: hidden)
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

    /// What each reminder says. Private on the lock screen (H-A5): the
    /// title is only "Your 9pm reminder", and the pill is named only in the
    /// body, which iOS hides until the phone is unlocked (Show Previews:
    /// When Unlocked, the iPhone default). If she shows previews always,
    /// the body stays as private as the title.
    static func content(for r: PillReminder, pillTime: Minutes, packLength: Int, bodyHiddenWhenLocked: Bool) -> UNMutableNotificationContent {
        let c = PrivateNotice.content(at: pillTime)
        c.categoryIdentifier = category
        guard bodyHiddenWhenLocked else { return c }
        switch r.kind {
        case .newPackTomorrow:
            c.body = "New pack tomorrow: pill 1 at \(Clock.format(pillTime)). Have your new pack with you."
        case .onTime where r.isNewPack:
            c.body = "New pack today: pill 1 of \(packLength). Starting on time matters most."
        case .onTime:
            c.body = "Pill \(r.packDay) of \(packLength)."
        case .followUp:
            c.body = "Pill \(r.packDay) of \(packLength) isn\u{2019}t marked taken yet."
        }
        return c
    }

    /// Pill notifications: the title stays on the lock screen while the
    /// body waits for Face ID.
    static let category = "pill"

    /// Adds the pill category to the app's others (replacing only its own).
    static func registerCategory() async {
        let center = UNUserNotificationCenter.current()
        let mine = UNNotificationCategory(identifier: category, actions: [], intentIdentifiers: [],
                                          hiddenPreviewsBodyPlaceholder: PrivateNotice.placeholder,
                                          options: [.hiddenPreviewsShowTitle])
        let others = await center.notificationCategories().filter { $0.identifier != category }
        center.setNotificationCategories(others.union([mine]))
    }
}

/// Lock-screen-private wording for anything about the pill, periods or mood
/// (H-A5): roommates and friends see lock screens, so the visible line is
/// just "Your 9pm reminder" and the rest waits until the phone is unlocked.
enum PrivateNotice {
    static let placeholder = "Unlock to see it"

    /// "Your 9pm reminder", with a body that says nothing more.
    static func content(at minutes: Minutes) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "Your \(Clock.format(minutes).replacingOccurrences(of: ":00", with: "")) reminder"
        c.body = "Open Health Dashboard to see it."
        return c
    }

    /// iOS keeps notification bodies off the lock screen until it's
    /// unlocked (her Show Previews setting isn't Always).
    static func bodyHiddenWhenLocked() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().showPreviewsSetting != .always
    }
}
