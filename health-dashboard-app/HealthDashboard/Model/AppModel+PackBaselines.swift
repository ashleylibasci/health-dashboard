import Foundation
import HealthCore

/// Pack-day baselines (E2): after three packs, if her resting heart rate or
/// HRV shifts in the break in every pack, recovery allows for it on break
/// days ("break week: your heart rate usually runs 1 beat higher"). If not,
/// nothing shows and nothing changes.
extension AppModel {
    /// Her break-week shift, from her nights' heart readings against her
    /// usual. Combined pill only.
    var packHeartShift: PackHeartShift? {
        guard store.birthControl == .combinedPill, let cal = packCalendar else { return nil }
        let packs = finishedPacks
        let key = "\(cal.start.timeIntervalSince1970)-\(cal.activeDays)-\(cal.packLength)-\(packs.last ?? 0)-\(nights.count)-\(nights.last?.wakeDay.timeIntervalSince1970 ?? 0)"
        if let cached = Self.packShiftCache, cached.key == key { return cached.value }
        var rhr: [Date: Double] = [:], hrv: [Date: Double] = [:]
        for n in nights {
            if let v = n.outcome.restingHRDelta { rhr[n.wakeDay] = v }
            if let v = n.outcome.hrvDeltaPct { hrv[n.wakeDay] = v }
        }
        let value = PackHeartShift.find(restingHRDelta: rhr, hrvDeltaPct: hrv, packs: packs, in: cal)
        Self.packShiftCache = (key, value)
        return value
    }

    /// The shift to allow for on `day`: her break-week shift on a break
    /// day, else none.
    func packHeartAllowance(on day: Date) -> PackHeartShift? {
        guard let shift = packHeartShift, let cal = packCalendar, cal.isBreak(day: cal.position(of: day).day) else { return nil }
        return shift
    }

    /// Today's, on the day she woke.
    var packHeartAllowanceToday: PackHeartShift? { packHeartAllowance(on: appDayDate) }

    /// "Allowed for: in your break week your resting heart rate usually
    /// runs 1 beat higher."
    var recoveryPackNote: String? {
        guard let s = packHeartAllowanceToday else { return nil }
        var parts: [String] = []
        if s.restingHR != 0 {
            let beats = max(1, Int(abs(s.restingHR).rounded()))
            parts.append("your resting heart rate usually runs \(beats) beat\(beats == 1 ? "" : "s") \(s.restingHR > 0 ? "higher" : "lower")")
        }
        if s.hrvPct != 0 {
            parts.append("your HRV usually runs \(Int(abs(s.hrvPct).rounded()))% \(s.hrvPct > 0 ? "higher" : "lower")")
        }
        return "Allowed for: in your \(packBreakName.lowercased()) " + parts.joined(separator: " and ") + ", from your last \(PackHeartShift.packsNeeded) packs."
    }

    private static var packShiftCache: (key: String, value: PackHeartShift?)?
}
