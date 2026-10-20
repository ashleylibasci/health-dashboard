import Foundation

/// Decides, from wrist movement, when she's in light sleep during the smart alarm window.
/// Light sleep and the brief wake-ups between cycles come with small shifts and turns; deep
/// sleep is very still. So the alarm goes off at the first stretch of restlessness.
///
/// Movement is summed into 30-second epochs (how sleep researchers score actigraphy). An epoch
/// counts as "moving" above `threshold`; two moving epochs within the last two minutes is
/// light sleep. A single twitch isn't enough.
struct WakeDetector {
    /// Average change in acceleration (g) per sample. Still in bed is about 0.002–0.005; turning
    /// over is well above 0.02. A starting guess, worth tuning against real nights.
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

/// When the next alarm should be: the latest wake time, and the window before it.
struct SmartAlarmPlan: Codable, Equatable {
    /// Minutes after midnight, e.g. 7:45am = 465.
    var latest: Int
    /// How early it may wake her, in minutes. The Watch allows a session of up to 30.
    var window: Int = 30
    var repeats = true

    /// The next time the latest wake time comes around after `now`.
    func nextLatest(after now: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: now)
        let today = calendar.date(byAdding: .minute, value: latest, to: midnight)!
        return today > now.addingTimeInterval(TimeInterval(window * 60)) ? today : calendar.date(byAdding: .day, value: 1, to: today)!
    }

    /// When the window opens and the Watch starts watching for light sleep.
    func windowStart(after now: Date, calendar: Calendar = .current) -> Date {
        nextLatest(after: now, calendar: calendar).addingTimeInterval(-TimeInterval(min(30, window) * 60))
    }

    var latestText: String {
        let t = (latest % 1440 + 1440) % 1440
        let h = t / 60, m = t % 60
        return String(format: "%d:%02d%@", h % 12 == 0 ? 12 : h % 12, m, h < 12 ? "am" : "pm")
    }
}
