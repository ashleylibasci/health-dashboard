import Foundation
import HealthKit

/// Apple's State of Mind log (F2): moods she logs in the Mindfulness app
/// on her Watch or iPhone count as her mood rating for days she didn't tap
/// one here. iOS 18 and later; read only.
@MainActor
enum MoodHealth {
    /// App day → mood 1–5. A day's latest "how I feel today" entry wins;
    /// without one, the average of that day's "right now" entries.
    /// Nil before iOS 18 or when Health can't be read.
    static func moods(_ store: HKHealthStore, days: Int) async -> [Date: Int]? {
        guard #available(iOS 18.0, *), HealthKitService.isAvailable else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.stateOfMind(HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: store) else { return nil }
        var daily: [Date: Double] = [:]
        var momentary: [Date: [Double]] = [:]
        for s in samples {
            let day = AppDay.day(containing: s.startDate)
            if s.kind == .dailyMood { daily[day] = s.valence } else { momentary[day, default: []].append(s.valence) }
        }
        var out: [Date: Int] = [:]
        for (day, values) in momentary { out[day] = rating(values.reduce(0, +) / Double(values.count)) }
        for (day, valence) in daily { out[day] = rating(valence) }
        return out
    }

    /// Valence −1 (very unpleasant) … 1 (very pleasant) on the app's 1–5
    /// mood scale: −1 is 1, 0 is 3, 1 is 5.
    static func rating(_ valence: Double) -> Int {
        min(max(Int(((min(max(valence, -1), 1) + 1) * 2).rounded()) + 1, 1), 5)
    }
}
