import Foundation
import Observation

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
            profile = nil
        }
        #endif
        healthState = !HealthReader.isAvailable ? .unavailable
            : UserDefaults.standard.bool(forKey: Self.connectedKey) ? .loading : .notConnected
        calendarState = Keychain.get(Self.calendarAccount) == nil ? .notConnected : .loading
        #if DEBUG
        if DemoData.isOn {
            health = DemoData.health()
            healthState = .ready
            events = DemoData.events()
            calendarState = .ready(checkedAt: .now)
            if profile == nil { profile = DemoData.profile() }
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
        } catch {
            healthState = .failed(error.localizedDescription)
        }
    }

    func refreshHealth() async {
        guard !isDemo, healthState != .unavailable, UserDefaults.standard.bool(forKey: Self.connectedKey) else { return }
        if health.nights.isEmpty { healthState = .loading }
        do {
            health = try await HealthReader.read()
            healthState = .ready
        } catch {
            healthState = .failed(error.localizedDescription)
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

    func setCalendarURL(_ url: String?) async {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(trimmed, for: Self.calendarAccount)
        events = []
        calendarState = trimmed?.isEmpty == false ? .loading : .notConnected
        await refreshCalendar()
    }

    func refreshCalendar() async {
        if isDemo { return }
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

    var examLens: ExamWeekLens? {
        examWeekLens(health.nights, restingHr: health.restingHr, hrv: health.hrv, examDates: exams.map(\.date))
    }
}
