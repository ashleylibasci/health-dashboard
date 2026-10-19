import EventKit
import Foundation
import Observation
import UserNotifications

/// What the screens need, read from Health and the calendar each time the app comes forward.
@MainActor
@Observable
final class AppModel {
    enum HealthState: Equatable { case notConnected, loading, ready, unavailable, failed(String) }
    enum CalendarState: Equatable { case notConnected, loading, ready(checkedAt: Date), failed(String) }

    private(set) var healthState: HealthState
    private(set) var health = HealthData()
    private(set) var calendarState: CalendarState
    private(set) var events: [CalendarEvent] = []

    /// Nil until the welcome flow is finished.
    var profile: Profile? = ProfileStore.load() {
        didSet { if !isDemo { ProfileStore.save(profile) } }
    }

    private static let connectedKey = "healthConnected"
    private static let calendarAccount = "calendarICSURL"

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetProfile") {
            ProfileStore.save(nil)
            UserDefaults.standard.removeObject(forKey: Self.connectedKey)
            Keychain.set(nil, for: Self.calendarAccount)
            UserDefaults.standard.removeObject(forKey: Self.sourceKey)
            GoogleAuth.shared.signOut()
            profile = nil
        }
        #endif
        healthState = !HealthReader.isAvailable ? .unavailable
            : UserDefaults.standard.bool(forKey: Self.connectedKey) ? .loading : .notConnected
        calendarState = Self.storedSource == nil ? .notConnected : .loading
        #if DEBUG
        if DemoData.isOn {
            health = DemoData.health()
            healthState = .ready
            events = DemoData.events()
            calendarState = .ready(checkedAt: .now)
            if !ProcessInfo.processInfo.arguments.contains("-step") { profile = DemoData.profile() }
        }
        #endif
    }

    /// Set when saving a log to Health fails, shown on the Log screen.
    var lastLogError: String?

    var isDemoMode: Bool { isDemo }

    private var isDemo: Bool {
        #if DEBUG
        DemoData.isOn
        #else
        false
        #endif
    }

    // MARK: Health

    var isHealthConnected: Bool { UserDefaults.standard.bool(forKey: Self.connectedKey) }

    /// Asks for Health access (Apple's sheet appears once) and reads the full history.
    func connectHealth() async {
        if isDemo {
            healthState = .ready
            return
        }
        do {
            try await HealthReader.requestAccess()
            UserDefaults.standard.set(true, forKey: Self.connectedKey)
            await refreshHealth()
            BackgroundHealth.shared.start(self)
        } catch {
            healthState = .failed(error.localizedDescription)
        }
    }

    /// `quiet` is for background wake-ups: Health can't be read while the phone is locked,
    /// so a failed background read keeps the last numbers instead of showing an error.
    func refreshHealth(quiet: Bool = false) async {
        guard !isDemo, healthState != .unavailable, UserDefaults.standard.bool(forKey: Self.connectedKey) else { return }
        if health.nights.isEmpty && !quiet { healthState = .loading }
        do {
            health = try await HealthReader.read()
            healthState = .ready
            if !quiet { BackgroundHealth.shared.noteRefreshed() }
        } catch {
            if !quiet || health.nights.isEmpty { healthState = quiet ? healthState : .failed(error.localizedDescription) }
        }
    }

    var weekend: WeekendShift? { weekendShift(health.nights) }
    var lateNight: LateNightCost? { lateNightCost(health.nights, restingHr: health.restingHr, hrv: health.hrv) }
    var lastWeek: [Night] { Array(health.nights.suffix(7)) }
    var recentLate: [Night] { Array(health.nights.filter { $0.bedtime >= lateBedtime }.suffix(3).reversed()) }
    var lastNight: Night? { health.nights.last }

    /// Typical resting HR and HRV over the 4 weeks before today, to compare today against.
    func typical(_ series: [String: Double]) -> Double? {
        let today = Day.key(.now)
        return median(series.filter { (1...28).contains(Day.between($0.key, today)) }.map(\.value))
    }

    // MARK: Calendar

    var calendarURL: String? { Keychain.get(Self.calendarAccount) }

    /// Where exams come from: Google (signed in with Google), the iPhone's calendar (Apple
    /// Calendar, plus any accounts added to the phone), or a Google secret link.
    enum CalendarSource: String { case google, apple, link }

    private static let sourceKey = "calendarSource"
    private let eventStore = EKEventStore()

    private static var storedSource: CalendarSource? {
        if let raw = UserDefaults.standard.string(forKey: sourceKey) { return CalendarSource(rawValue: raw) }
        // Earlier versions: a saved link, or the "use this iPhone's calendar" switch.
        if UserDefaults.standard.bool(forKey: "useDeviceCalendar") { return .apple }
        return Keychain.get(calendarAccount) != nil ? .link : nil
    }

    var calendarSource: CalendarSource? { Self.storedSource }
    var isCalendarConnected: Bool { calendarSource != nil }
    var googleConfigured: Bool { GoogleAuth.shared.isConfigured }

    private func setSource(_ source: CalendarSource?) {
        UserDefaults.standard.set(source?.rawValue, forKey: Self.sourceKey)
        UserDefaults.standard.removeObject(forKey: "useDeviceCalendar")
        if source != .google { GoogleAuth.shared.signOut() }
        if source != .link { Keychain.set(nil, for: Self.calendarAccount) }
        events = []
        calendarState = source == nil ? .notConnected : .loading
    }

    /// Opens Google's sign-in page and reads Google Calendar directly.
    func connectGoogle() async {
        if isDemo { return }
        do {
            try await GoogleAuth.shared.signIn()
            setSource(.google)
            await refreshCalendar()
        } catch GoogleError.cancelled {
            // Back to the choices, nothing changed.
        } catch {
            calendarState = .failed(error.localizedDescription)
        }
    }

    /// Asks iOS for calendar access and reads the iPhone's calendars (Apple Calendar).
    func connectDeviceCalendar() async {
        if isDemo { return }
        do {
            guard try await eventStore.requestFullAccessToEvents() else {
                calendarState = .failed("Calendar access is off. Turn it on in the Settings app → Privacy & Security → Calendars → Health Dashboard.")
                return
            }
            setSource(.apple)
            await refreshCalendar()
        } catch {
            calendarState = .failed(error.localizedDescription)
        }
    }

    func disconnectCalendar() async {
        setSource(nil)
    }

    func setCalendarURL(_ url: String?) async {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            if calendarSource == .link { setSource(nil) }
            return
        }
        setSource(.link)
        Keychain.set(trimmed, for: Self.calendarAccount)
        await refreshCalendar()
    }

    private func readDeviceCalendar() {
        eventStore.reset()
        let start = Calendar.current.date(byAdding: .day, value: -365, to: .now)!
        let end = Calendar.current.date(byAdding: .day, value: 60, to: .now)!
        events = eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !$0.hasRecurrenceRules }
            .map { e in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: e.startDate)
                return CalendarEvent(title: e.title ?? "", date: Day.key(e.startDate), minutes: e.isAllDay ? nil : (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
            .sorted { ($0.date, $0.minutes ?? -1) < ($1.date, $1.minutes ?? -1) }
        calendarState = .ready(checkedAt: .now)
    }

    func refreshCalendar() async {
        if isDemo { return }
        switch calendarSource {
        case nil:
            calendarState = .notConnected
            return
        case .google?:
            do {
                events = try await GoogleCalendarAPI.events()
                calendarState = .ready(checkedAt: .now)
            } catch {
                calendarState = .failed(error.localizedDescription)
            }
            return
        case .apple?:
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                calendarState = .failed("Calendar access is off. Turn it on in the Settings app → Privacy & Security → Calendars → Health Dashboard.")
                return
            }
            readDeviceCalendar()
            return
        case .link?:
            break
        }
        guard let link = calendarURL else {
            calendarState = .notConnected
            return
        }
        // Google shows the link as https; some copies arrive as webcal://.
        guard let url = URL(string: link.replacingOccurrences(of: "webcal://", with: "https://")) else {
            calendarState = .failed("That doesn’t look like a link. Copy the secret address again.")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else {
                calendarState = .failed("Google didn’t accept that link. Copy the secret address in iCal format again.")
                return
            }
            events = parseICS(text)
            calendarState = .ready(checkedAt: .now)
        } catch {
            calendarState = .failed("Couldn’t reach Google Calendar. Check your connection.")
        }
    }

    var exams: [CalendarEvent] { events.filter { isExam($0.title) } }

    /// Exams from today through the next 3 weeks.
    var upcomingExams: [CalendarEvent] {
        let today = Day.key(.now)
        return exams.filter { (0...21).contains(Day.between(today, $0.date)) }
    }

    // MARK: Reminders

    var notificationsAllowed: Bool?

    /// Asks once, from the welcome flow or Settings, never as a surprise.
    func requestNotifications() async {
        if isDemo { notificationsAllowed = true; return }
        notificationsAllowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        await scheduleNotifications()
    }

    func checkNotifications() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsAllowed = status == .notDetermined ? nil : status == .authorized
    }

    // MARK: History check

    /// True when Health only shared about a month, which usually means "Past 30 Days" was picked
    /// on Apple's permission sheet instead of "All Recorded Data".
    var historyLooksShort: Bool {
        let firsts = [health.nights.first?.date, health.restingHr.keys.min(), health.steps.keys.min()].compactMap { $0 }
        guard let earliest = firsts.min() else { return false }
        return Day.between(earliest, Day.key(.now)) <= 35
    }

    var examLens: ExamWeekLens? {
        examWeekLens(health.nights, restingHr: health.restingHr, hrv: health.hrv, examDates: exams.map(\.date))
    }
}
