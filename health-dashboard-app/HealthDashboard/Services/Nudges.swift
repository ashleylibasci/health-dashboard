import Foundation
import UserNotifications
import HealthCore

/// Local notifications for the "Peak and dip nudges" and "Sick alerts"
/// settings, and the smart-alarm arming reminder. Everything is scheduled
/// on the phone; nothing leaves it.
///
/// - Peak and dip: one notification 15 minutes before the first peak and
///   one before the dip, for the rest of today and for tomorrow (from
///   tonight's plan, so they come even if she doesn't open the app),
///   rescheduled every time the data refreshes.
/// - Sick alerts: at most one a day, when the signals say "Possible" or
///   "Likely". Never at night: after 10pm or before 8am it waits until 8am.
/// - Smart alarm: "Open the app on your Watch" the evening before a
///   morning the Watch hasn't armed yet.
enum Nudges {
    static let nudgePrefix = "nudge-"
    static let sickPrefix = "sick-"
    static let alarmPrefix = "alarm-arm-"
    static let lead = 15

    struct Plan: Hashable {
        var identifier: String
        var fire: Date
        var title: String
        var body: String
    }

    // MARK: Peak and dip

    /// A day's nudges that are still ahead: 15 minutes before the first peak
    /// and before the dip. `appDay` is midnight of the app day the zone
    /// minutes are relative to; `tag` keeps tomorrow's ids apart from today's.
    static func peakDipPlan(zones: [EnergyDay.Zone], appDay: Date, now: Date = .now, tag: String = "") -> [Plan] {
        var out: [Plan] = []
        for zone in zones {
            let body: String
            switch zone.kind {
            case .morningPeak:
                body = "Your sharpest stretch starts at \(Clock.format(zone.range.start)). A good time for your hardest work."
            case .afternoonDip:
                body = "Your energy dips from \(Clock.format(zone.range.start)). Plan easier tasks. Daylight or a short break helps more than caffeine late in the day."
            default:
                continue
            }
            let fire = AppDay.date(zone.range.start - lead, relativeTo: appDay)
            guard fire > now else { continue }
            out.append(Plan(identifier: nudgePrefix + tag + zone.kind.rawValue, fire: fire,
                            title: "\(zone.title) in 15 minutes", body: body))
        }
        return out
    }

    /// Replaces any pending peak/dip nudges with `plans`. Doesn't ask for
    /// permission; does nothing if notifications aren't allowed.
    static func reschedulePeakDip(_ plans: [Plan]) async {
        await cancel(prefix: nudgePrefix)
        guard await isAllowed() else { return }
        for p in plans { await add(p) }
    }

    static func cancelPeakDip() async { await cancel(prefix: nudgePrefix) }

    // MARK: Sick alerts

    private static let lastSickAlertKey = "nudges.lastSickAlertDay"

    /// When a sick alert found at `now` should arrive: right away during the
    /// day, else 8:00am (the same morning before 8am, the next one after 10pm).
    static func sickAlertTime(now: Date = .now, calendar: Calendar = .current) -> Date? {
        let hour = calendar.component(.hour, from: now)
        guard hour >= 22 || hour < 8 else { return nil }
        let day = hour >= 22 ? (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now) : calendar.startOfDay(for: now)
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day)
    }

    /// One notification if the signals reached "Possible" or "Likely" and
    /// none was sent for that day. Marked as sent only once the system took
    /// it. `cyclePhaseUnknown`: says the app couldn't allow for her cycle.
    static func sickAlertIfNeeded(_ confidence: IllnessSignal.Confidence, cyclePhaseUnknown: Bool = false, now: Date = .now) async {
        guard confidence == .medium || confidence == .high else { return }
        let cal = Calendar.current
        let later = sickAlertTime(now: now, calendar: cal)
        let day = cal.startOfDay(for: later ?? now)
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: lastSickAlertKey) as? Date, cal.isDate(last, inSameDayAs: day) { return }
        guard await isAllowed() else { return }
        let id = sickPrefix + String(Int(day.timeIntervalSince1970))
        var body = confidence == .high
            ? "Several of your overnight signals are off at once. Rest if you can, and see how you feel."
            : "A couple of your overnight signals are off. Worth an easier day."
        if cyclePhaseUnknown {
            body += " Your cycle can raise these too, and the app can't tell which phase you're in."
        }
        let content = UNMutableNotificationContent()
        content.title = confidence == .high ? "You might be getting sick" : "Your body may be fighting something"
        content.body = body
        content.sound = .default
        let trigger = later.map {
            UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: $0), repeats: false)
        }
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            defaults.set(day, forKey: lastSickAlertKey)
        } catch {
            // Not scheduled: try again on the next refresh.
        }
    }

    // MARK: Smart alarm

    /// "Open the app on your Watch", the evening before a morning the Watch
    /// hasn't armed (it can only arm while its app is open). Replaces any
    /// earlier one.
    static func scheduleAlarmArm(at fire: Date, wakeTime: Date) async {
        await cancel(prefix: alarmPrefix)
        guard await isAllowed() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Arm tomorrow's smart alarm"
        content.body = "Open Health Dashboard on your Apple Watch before bed so it can wake you by \(Clock.format(Clock.minutesOfDay(wakeTime)))."
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alarmPrefix + String(Int(fire.timeIntervalSince1970)),
                                                                                content: content, trigger: trigger))
    }

    static func cancelAlarmArm() async { await cancel(prefix: alarmPrefix) }

    // MARK: Permission

    /// Asks for permission (only shows the system prompt the first time).
    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAllowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    // MARK: Helpers

    private static func add(_ p: Plan) async {
        let content = UNMutableNotificationContent()
        content.title = p.title
        content.body = p.body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: p.identifier, content: content, trigger: trigger))
    }

    private static func cancel(prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

/// Shows the app's notifications (sick alert, nudges) as banners while the
/// app is open; without it iOS drops them silently in the foreground. Set as
/// the notification center's delegate at launch.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// Call once at launch.
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }
}
