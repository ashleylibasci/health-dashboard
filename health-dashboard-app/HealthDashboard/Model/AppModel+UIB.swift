import Foundation
import HealthCore

/// Derived values for the Body, Log, Cycle, Settings and onboarding screens
/// (pack prompts, skipped breaks, caffeine copy). Computed only; nothing
/// here is stored.
extension AppModel {
    // MARK: Pack

    /// "pill", "ring", "patch".
    var packThing: String {
        switch store.birthControl {
        case .ring?: return "ring"
        case .patch?: return "patch"
        default: return "pill"
        }
    }

    /// "start your new pack", "put in a new ring", "put on a new patch".
    var newPackPhrase: String {
        switch store.birthControl {
        case .ring?: return "put in a new ring"
        case .patch?: return "start a new patch cycle"
        default: return "start your new pack"
        }
    }

    /// She chose to skip this pack's break: the next pack starts on a day
    /// still ahead (`setPackStart` with a future date).
    var packSkippingBreak: Bool {
        guard packMethod != nil, let start = store.data.packStartDate else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: start) > cal.startOfDay(for: .now)
    }

    /// The day her next pack starts (pill 1 again).
    var nextPackStart: Date? {
        if packSkippingBreak { return store.data.packStartDate }
        guard let day = packDay else { return nil }
        return packPosition(day: day).newPackStart
    }

    /// Undo "skip this break": the pack start goes back to where it was.
    func undoSkipBreak() {
        guard packSkippingBreak, let start = store.data.packStartDate else { return }
        let back = Calendar.current.date(byAdding: .day, value: -max(store.data.packActiveDays, 1), to: start) ?? start
        setPackStart(back)
    }

    /// Whether "Skip this break" makes sense today: a pack with a break,
    /// the day known, not already skipping.
    var canSkipThisBreak: Bool {
        guard let p = packState, p.hasBreak, !packSkippingBreak, store.data.packStartDate != nil else { return false }
        return true
    }

    /// "Pill 9 of 28 · active · break week starts Mon, Nov 9", aware of a
    /// skipped break: "Pill 18 of 28 · active · skipping the break · next
    /// pack Mon, Nov 9". Nil when the pack day isn't known.
    var packSummaryLineShown: String? {
        guard let method = packMethod, let day = packDay else { return nil }
        let pos = packPosition(day: day)
        let unit = PackPosition.unit(for: method)
        if packSkippingBreak, let next = store.data.packStartDate {
            return ["\(unit) \(day) of \(pos.packLength)", "active", "skipping the \(pos.breakName)",
                    "next pack \(PackPosition.shortDate(next))"].joined(separator: " \u{00B7} ")
        }
        return pos.summary(unit: unit)
    }

    /// The pack day a date falls on (for "you logged bleeding on pill 12").
    func packDay(on date: Date) -> Int? {
        guard let today = packDay else { return nil }
        let cal = Calendar.current
        let ago = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: .now)).day ?? 0
        let length = max(store.data.packLength, 1)
        return ((today - 1 - ago) % length + length) % length + 1
    }

    // MARK: Caffeine copy

    /// "4:30pm" or, when the cutoff for a typical drink comes before she's
    /// up, "one small drink early".
    var caffeineCutoffText: String {
        caffeineCutoffShown.map { Clock.format($0) } ?? "one small drink early"
    }

    /// The short version for tight spots ("4:30pm", "Early only").
    var caffeineCutoffShort: String {
        caffeineCutoffShown.map { BodyLogStyle.shortTime($0) } ?? "early only"
    }

    /// The copy for when there's no safe clock time for a typical drink.
    var caffeineEarlyOnlyText: String {
        let cause = caffeineLastsLonger
            ? "On your birth control, caffeine stays in your body about twice as long."
            : "With your bedtime, caffeine has little time to clear."
        let largest = caffeineLargestDoseAtWake
        let left = caffeineLeftAtBedtime(mg: 95, at: caffeineWakeTime)
        let advice = largest >= 5
            ? "Best: one small drink soon after you wake, up to about \(largest) mg."
            : "Best: skip caffeine today, or keep it very small and early."
        return "\(cause) Even a regular coffee (95 mg) right when you wake leaves about \(left) mg at bedtime. \(advice)"
    }

    // MARK: Cycle copy

    /// "Due around now" applies (past her usual length, a method whose
    /// periods can be counted on). Not on the hormonal IUD or mini pill.
    var showsDueAroundNow: Bool { periodDueAroundNow && !hidesPeriodCountdownOnScreens }

    /// "your usual 31 days" or "a typical 29 days".
    func usualLengthPhrase(_ length: Int) -> String {
        cycleLengthIsPersonal ? "your usual \(length) days" : "a typical \(length) days"
    }

    /// Why the irregular view shows when she didn't pick it, in one line.
    var irregularReasonText: String? {
        switch irregularReason {
        case "pcos"?: return "Showing the irregular view because PCOS is on in Health conditions."
        case "long"?: return "Showing the irregular view because your cycles run longer than 45 days, so there\u{2019}s no usual length to count against."
        default: return nil
        }
    }
}
