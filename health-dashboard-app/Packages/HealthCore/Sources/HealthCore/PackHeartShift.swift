import Foundation

/// Pack-day baselines (H-E2): after three packs, whether her own resting
/// heart rate or HRV runs differently in the break. On the combined pill
/// there's usually nothing to find (Okafor), so this is a personal test:
/// only a shift in the same direction in every one of the last three packs
/// counts, and nothing shows otherwise.
public struct PackHeartShift: Hashable, Sendable {
    /// Break minus active-pill days, bpm (0 when it doesn't shift).
    public var restingHR: Double
    /// Break minus active-pill days, % of her usual (0 when it doesn't shift).
    public var hrvPct: Double

    public init(restingHR: Double, hrvPct: Double) {
        self.restingHR = restingHR
        self.hrvPct = hrvPct
    }

    public static let packsNeeded = 3
    /// The smallest shift that counts: 1 bpm, 5% HRV (about the luteal
    /// shift `CycleHeartShift` allows for on a natural cycle).
    public static let minRestingHR = 1.0
    public static let minHRVPct = 5.0
    /// The most it allows for, whatever her packs show.
    public static let maxRestingHR = 2.0
    public static let maxHRVPct = 8.0
    /// Readings a pack needs on break days and on active days.
    public static let breakReadings = 4
    public static let activeReadings = 10

    /// From her daily changes against her usual (bpm and %), by day. nil
    /// before three finished packs with enough readings, or when neither
    /// shifts.
    public static func find(restingHRDelta: [Date: Double], hrvDeltaPct: [Date: Double], packs: [Int],
                            in calendar: PackCalendar, cal: Calendar = .current) -> PackHeartShift? {
        guard calendar.hasBreak, packs.count >= packsNeeded else { return nil }
        let used = Array(packs.suffix(packsNeeded))
        func shift(_ byDay: [Date: Double], min: Double, max cap: Double) -> Double {
            var diffs: [Double] = []
            for pack in used {
                var b: [Double] = [], a: [Double] = []
                for (day, v) in byDay {
                    let at = calendar.position(of: day, calendar: cal)
                    guard at.pack == pack else { continue }
                    if calendar.isBreak(day: at.day) { b.append(v) } else { a.append(v) }
                }
                guard b.count >= breakReadings, a.count >= activeReadings, let mb = b.mean, let ma = a.mean else { return 0 }
                diffs.append(mb - ma)
            }
            let sameWay = diffs.allSatisfy { $0 > 0 } || diffs.allSatisfy { $0 < 0 }
            guard sameWay, let mean = diffs.mean, abs(mean) >= min else { return 0 }
            return Swift.min(Swift.max(mean, -cap), cap)
        }
        let rhr = shift(restingHRDelta, min: minRestingHR, max: maxRestingHR)
        let hrv = shift(hrvDeltaPct, min: minHRVPct, max: maxHRVPct)
        guard rhr != 0 || hrv != 0 else { return nil }
        return PackHeartShift(restingHR: rhr, hrvPct: hrv)
    }
}
