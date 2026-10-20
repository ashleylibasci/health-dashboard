import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Decides, from wrist movement, when she's in light sleep during the smart alarm window.
/// Light sleep and the brief wake-ups between cycles come with small shifts and turns; deep
/// sleep is very still. So the alarm goes off at the first stretch of restlessness.
///
/// Movement is summed into 30-second epochs (how sleep researchers score actigraphy). An epoch
/// counts as "moving" above `threshold`; two moving epochs within the last two minutes is
/// light sleep. A single twitch isn't enough.
struct WakeDetector {
    /// Average change in acceleration (g) per sample. Still in bed is about 0.002–0.005; turning
    /// over is well above 0.02. Set from her sensitivity choice (`SmartAlarmPlan.Sensitivity`).
    var threshold = 0.012
    var epochsNeeded = 2
    var lookback = 4
    private(set) var epochs: [Double] = []

    init(threshold: Double = 0.012) { self.threshold = threshold }

    /// Adds one epoch's average movement. True once she looks to be in light sleep.
    mutating func add(_ movement: Double) -> Bool {
        epochs.append(movement)
        return epochs.suffix(lookback).filter { $0 >= threshold }.count >= epochsNeeded
    }

    /// Average change in the size of acceleration between samples: 0 when perfectly still.
    /// Uses the size so it doesn't matter which way the wrist is lying.
    static func movement(_ samples: [(x: Double, y: Double, z: Double)]) -> Double {
        let size = samples.map { ($0.x * $0.x + $0.y * $0.y + $0.z * $0.z).squareRoot() }
        guard size.count >= 2 else { return 0 }
        return zip(size, size.dropFirst()).map { abs($1 - $0) }.reduce(0, +) / Double(size.count - 1)
    }
}

/// One morning's alarm, for the log that shows how early it tends to wake her.
struct AlarmMorning: Codable, Equatable, Identifiable {
    var date: Date
    /// Minutes before the latest time it went off; 0 when it waited for the latest time.
    var minutesEarly: Int
    /// The busiest 30 seconds of movement in the window, to compare against the threshold.
    var peakMovement: Double
    var id: Date { date }
}

/// What the Watch tells the iPhone about the smart alarm, so the phone can show whether it's set.
/// The Watch also keeps the latest one in the App Group for the watch-face complication.
struct WatchAlarmStatus: Codable, Equatable {
    enum State: String, Codable { case armed, waiting, failed, off }
    var state: State
    /// The latest wake time it's set for, when armed.
    var latest: Date?
    var plan: SmartAlarmPlan?
    var message: String?
    /// The last two weeks of mornings, newest last.
    var mornings: [AlarmMorning] = []

    init(state: State, latest: Date? = nil, plan: SmartAlarmPlan? = nil, message: String? = nil, mornings: [AlarmMorning] = []) {
        self.state = state; self.latest = latest; self.plan = plan; self.message = message; self.mornings = mornings
    }

    /// Older Watch builds sent no mornings; read what's there.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(State.self, forKey: .state)
        latest = try c.decodeIfPresent(Date.self, forKey: .latest)
        plan = try c.decodeIfPresent(SmartAlarmPlan.self, forKey: .plan)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        mornings = try c.decodeIfPresent([AlarmMorning].self, forKey: .mornings) ?? []
    }

    /// Set and still ahead (a status saved before the alarm went off reads as no longer set).
    var isSet: Bool { isSet(at: .now) }

    /// The same, as of `date`: the watch face draws its entries ahead of time.
    func isSet(at date: Date) -> Bool { state == .armed && (latest ?? .distantPast) > date }

    private static let key = "watchAlarmStatus.v1"

    static func load() -> WatchAlarmStatus? {
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.data(forKey: key).flatMap { try? JSONDecoder().decode(WatchAlarmStatus.self, from: $0) }
    }

    /// Saves it for the complication and asks the watch face to redraw.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.set(data, forKey: Self.key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

/// When the next alarm should be: the latest wake time, and the window before it.
struct SmartAlarmPlan: Codable, Equatable {
    /// Minutes after midnight, e.g. 7:45am = 465.
    var latest: Int
    /// How early it may wake her, in minutes. The Watch allows a session of up to 30.
    var window: Int = 30
    var repeats = true
    var sensitivity: Sensitivity = .normal
    /// Also set a regular iPhone alarm at the latest time, cancelled if the Watch wakes her first.
    var phoneBackup = false

    /// How much movement counts as light sleep. "Gentle" needs more stirring before it wakes
    /// her (so it tends to wake her later); "Sensitive" goes off at smaller movements.
    enum Sensitivity: String, Codable, CaseIterable, Identifiable {
        case gentle, normal, sensitive
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        var threshold: Double {
            switch self {
            case .gentle: 0.018
            case .normal: 0.012
            case .sensitive: 0.008
            }
        }
    }

    init(latest: Int, window: Int = 30, repeats: Bool = true, sensitivity: Sensitivity = .normal, phoneBackup: Bool = false) {
        self.latest = latest; self.window = window; self.repeats = repeats; self.sensitivity = sensitivity; self.phoneBackup = phoneBackup
    }

    /// Plans saved before a setting existed get its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latest = try c.decode(Int.self, forKey: .latest)
        window = try c.decodeIfPresent(Int.self, forKey: .window) ?? 30
        repeats = try c.decodeIfPresent(Bool.self, forKey: .repeats) ?? true
        sensitivity = try c.decodeIfPresent(Sensitivity.self, forKey: .sensitivity) ?? .normal
        phoneBackup = try c.decodeIfPresent(Bool.self, forKey: .phoneBackup) ?? false
    }

    /// The next time the latest wake time comes around: today if it's still ahead, else tomorrow.
    /// Built from the clock time (not midnight plus minutes), so a daylight-saving night stays right.
    func nextLatest(after now: Date, calendar: Calendar = .current) -> Date {
        let t = (latest % 1440 + 1440) % 1440
        let today = calendar.date(bySettingHour: t / 60, minute: t % 60, second: 0, of: now)!
        return today > now.addingTimeInterval(2 * 60) ? today : calendar.date(byAdding: .day, value: 1, to: today)!
    }

    /// When the window opens and the Watch starts watching for light sleep: `window` minutes
    /// (at most the Watch's 30) before the latest time, or in a minute if that's already passed.
    func windowStart(after now: Date, calendar: Calendar = .current) -> Date {
        let latest = nextLatest(after: now, calendar: calendar)
        return max(latest.addingTimeInterval(-TimeInterval(min(30, window) * 60)), now.addingTimeInterval(60))
    }

    var latestText: String {
        let t = (latest % 1440 + 1440) % 1440
        let h = t / 60, m = t % 60
        return String(format: "%d:%02d%@", h % 12 == 0 ? 12 : h % 12, m, h < 12 ? "am" : "pm")
    }
}
