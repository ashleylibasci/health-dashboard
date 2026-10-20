import EventKit
import HealthKit
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
    private(set) var health = HealthData() {
        didSet { derived = Derived(health) }
    }

    /// Slow-to-compute numbers, worked out once whenever Health is re-read instead of on every screen draw.
    struct Derived {
        var recovery: [RecoveryDay] = []
        var recoveryByDate: [String: Int] = [:]
        init() {}
        init(_ h: HealthData) {
            recovery = recoveryDays(h.nights, restingHr: h.restingHr, hrv: h.hrv, days: 180)
            recoveryByDate = Dictionary(recovery.map { ($0.date, $0.score) }, uniquingKeysWith: { a, _ in a })
        }
    }
    private(set) var derived = Derived()
    @ObservationIgnored private var _calendarRefreshing = false
    @ObservationIgnored private var lastCalendarCheck = Date.distantPast
    /// The profile from before "Run the welcome setup again", so the welcome screens start filled in
    /// and pill-pack history isn't lost.
    @ObservationIgnored var previousProfile: Profile?

    func rerunWelcome() {
        previousProfile = profile
        profile = nil
    }
    private(set) var calendarState: CalendarState
    private(set) var events: [CalendarEvent] = []

    /// Nil until the welcome flow is finished.
    var profile: Profile? = ProfileStore.load() {
        didSet { if !isDemo { ProfileStore.save(profile) } }
    }

    private static let connectedKey = "healthConnected"
    private static let calendarAccount = "calendarICSURL"

    init() {
        // Keychain items survive deleting the app, but nothing else does. On a fresh install,
        // drop a leftover calendar link or Google sign-in so it doesn't reconnect by itself.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "installed.v1") {
            if defaults.object(forKey: Self.connectedKey) == nil && ProfileStore.load() == nil {
                Keychain.set(nil, for: Self.calendarAccount)
                Keychain.set(nil, for: "googleRefreshToken")
            }
            defaults.set(true, forKey: "installed.v1")
        }
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
            derived = Derived(health)
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
        // An update added new kinds of data: ask about just those (Apple's sheet appears once).
        if !quiet, await HealthReader.needsPermissionPrompt() { try? await HealthReader.requestAccess() }
        do {
            health = try await HealthReader.read()
            healthState = .ready
        } catch let error as HKError where error.code == .errorDatabaseInaccessible {
            // The phone is locked, so iOS keeps Health data out of reach. That isn't a problem to
            // show: keep the last numbers (or keep "loading") and read again as soon as it unlocks.
            if health.nights.isEmpty && health.restingHr.isEmpty { healthState = .loading }
        } catch {
            // Keep showing the last numbers if there are any; only a first read with nothing shows an error.
            if !quiet && health.nights.isEmpty && health.restingHr.isEmpty { healthState = .failed(error.localizedDescription) }
        }
    }

    /// Called when the phone is unlocked: anything that failed while it was locked gets read now.
    func phoneUnlocked() async {
        await refreshHealth()
        await refreshCalendar()
        if healthState == .ready { publishWidgetSnapshot() }
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
    private var calendarRefreshing: Bool {
        get { _calendarRefreshing }
        set { _calendarRefreshing = newValue }
    }
    private let eventStore = EKEventStore()

    private static var storedSource: CalendarSource? {
        if let raw = UserDefaults.standard.string(forKey: sourceKey) { return CalendarSource(rawValue: raw) }
        // Earlier versions: a saved link, or the "use this iPhone's calendar" switch.
        if UserDefaults.standard.bool(forKey: "useDeviceCalendar") { return .apple }
        return Keychain.get(calendarAccount) != nil ? .link : nil
    }

    var calendarSource: CalendarSource? { Self.storedSource }
    /// Google rejected the saved sign-in; Settings and Exams offer to sign in again.
    var googleNeedsSignIn: Bool { calendarSource == .google && !GoogleAuth.shared.isSignedIn }
    var isCalendarConnected: Bool { calendarSource != nil }
    var googleConfigured: Bool { GoogleAuth.shared.isConfigured }

    private func setSource(_ source: CalendarSource?) {
        UserDefaults.standard.set(source?.rawValue, forKey: Self.sourceKey)
        UserDefaults.standard.removeObject(forKey: "useDeviceCalendar")
        if source != .google { GoogleAuth.shared.signOut() }
        if source != .link { Keychain.set(nil, for: Self.calendarAccount) }
        events = []
        lastCalendarCheck = .distantPast
        calendarState = source == nil ? .notConnected : .loading
        // No calendar means no exams: drop exam reminders now, not at the next app open.
        if source == nil {
            let center = UNUserNotificationCenter.current()
            Task {
                let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("exam-") }
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    /// Opens Google's sign-in page and reads Google Calendar directly.
    func connectGoogle() async {
        if isDemo { return }
        do {
            try await GoogleAuth.shared.signIn()
            setSource(.google)
            await refreshCalendar(force: true)
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
            await refreshCalendar(force: true)
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
        await refreshCalendar(force: true)
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

    /// Skips if a refresh is already running, or the last good one was under 5 minutes ago
    /// (pass `force` for pull-to-refresh and right after connecting).
    func refreshCalendar(force: Bool = false) async {
        if isDemo || calendarRefreshing { return }
        if !force, case .ready = calendarState, Date.now.timeIntervalSince(lastCalendarCheck) < 300 { return }
        calendarRefreshing = true
        defer {
            calendarRefreshing = false
            if case .ready = calendarState { lastCalendarCheck = .now }
        }
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
