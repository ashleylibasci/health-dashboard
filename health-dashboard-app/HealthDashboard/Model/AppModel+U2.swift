import Foundation
import HealthCore

/// Small derived values for the Body, Log, Cycle, Settings and onboarding
/// screens. Computed only; nothing here is stored.
extension AppModel {
    // MARK: Pill pack

    /// The method she uses a pack for (combined pill, ring, patch), if any.
    var packMethod: BirthControl? {
        guard let bc = store.birthControl, bc.hasBreakWeek else { return nil }
        return bc
    }

    /// True when the pack day is only a guess from her last bleed (she hasn't
    /// said where she is in her pack).
    var packDayIsEstimated: Bool { packDay != nil && store.data.packStartDate == nil }

    /// What her pack looks like on `day` of it, from the pack type in settings.
    func packPosition(day: Int) -> PackPosition {
        PackPosition(day: day, activeDays: store.data.packActiveDays, packLength: max(store.data.packLength, 1),
                     appDay: Calendar.current.startOfDay(for: .now))
    }

    // MARK: Pack checks

    /// The start of the pack she's on now, counting on from the start she
    /// set (nil when she hasn't set one, or it's in the future).
    var currentPackStart: Date? {
        guard let start = store.data.packStartDate else { return nil }
        let cal = Calendar.current
        let length = max(store.data.packLength, 1)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: .now)).day ?? 0
        guard days >= 0 else { return nil }
        return cal.date(byAdding: .day, value: (days / length) * length, to: cal.startOfDay(for: start))
    }

    /// The app rolled her into a new pack on its own in the last 3 days
    /// (she never confirmed it): ask "Did you start your new pack on
    /// `packCheckNewPackDate`? Yes / I started on…". Answer with
    /// `confirmNewPack()`, `setPackStart(_:)` or `dismissPackCheck()`.
    var packNeedsCheck: Bool {
        guard packMethod != nil, let start = store.data.packStartDate, let current = currentPackStart else { return false }
        let cal = Calendar.current
        guard !cal.isDate(current, inSameDayAs: start) else { return false }
        let into = cal.dateComponents([.day], from: current, to: cal.startOfDay(for: .now)).day ?? 99
        guard into <= 2 else { return false }
        if let dismissed = store.data.packCheckDismissed, cal.isDate(dismissed, inSameDayAs: current) { return false }
        return true
    }

    /// The day the app assumed her new pack started (for the pack check).
    var packCheckNewPackDate: Date? { packNeedsCheck ? currentPackStart : nil }

    /// "Yes, I started it then."
    func confirmNewPack() {
        if let current = currentPackStart { setPackStart(current) }
    }

    /// "Not now" on either pack check: it won't ask again about this pack
    /// (or this bleed).
    func dismissPackCheck() {
        if packNeedsCheck, let current = currentPackStart {
            store.data.packCheckDismissed = current
        } else if let bleed = packBleedOutsideBreakDate {
            store.data.packCheckDismissed = bleed
        }
    }

    /// The last bleed she logged started in the last 3 days, well before her
    /// break (on active pills, more than 3 days before the break): maybe the
    /// pack day is off ("Bleeding on active pills? Check your pack day").
    /// Spotting on active pills is common and doesn't count.
    var packBleedOutsideBreakDate: Date? {
        guard packMethod != nil, store.data.packStartDate != nil, let p = packState, p.hasBreak, !p.isBreak,
              let bleed = loggedPeriodStarts.last else { return nil }
        let cal = Calendar.current
        let ago = cal.dateComponents([.day], from: bleed, to: cal.startOfDay(for: .now)).day ?? 99
        guard ago <= 2, p.day - ago <= p.activeDays - 3, p.day - ago >= 1 else { return nil }
        if let dismissed = store.data.packCheckDismissed, cal.isDate(dismissed, inSameDayAs: bleed) { return nil }
        return bleed
    }
    var packBleedOutsideBreak: Bool { packBleedOutsideBreakDate != nil }

    /// Skip this pack's break: the next pack starts the day the break would
    /// have (or today, if she's already in it).
    func skipThisBreak() {
        guard let p = packState, p.hasBreak else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let next = p.isBreak ? today : (cal.date(byAdding: .day, value: p.activeDays - p.day + 1, to: today) ?? today)
        setPackStart(next)
    }

    /// "Pill 9 of 28 · active · break week starts Mon, Nov 9". Nil when the
    /// pack day isn't known.
    var packSummaryLine: String? {
        guard let method = packMethod, let day = packDay else { return nil }
        return packPosition(day: day).summary(unit: PackPosition.unit(for: method))
    }

    // MARK: Period countdown

    /// No countdown, predicted period days or "period expected" wording:
    /// everything `hidesPeriodCountdown` covers, plus the hormonal IUD
    /// (periods often get lighter or stop, so a date would mislead).
    var hidesPeriodCountdownOnScreens: Bool { hidesPeriodCountdown || store.birthControl == .hormonalIUD }

    /// Days until the next period for the countdown on screen (nil when
    /// `hidesPeriodCountdownOnScreens`).
    var periodCountdownDays: Int? { hidesPeriodCountdownOnScreens ? nil : daysToPredictedPeriod }

    /// Start of the next period for the estimate card, counted from the
    /// calendar day (the one day definition every cycle date uses).
    var periodEstimateStart: Date? {
        guard let days = periodCountdownDays else { return nil }
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: .now))
    }

    // MARK: Conditions

    /// PMDD: the 988 crisis line stays on the Body and Cycle screens.
    var showsCrisisLine: Bool { store.data.conditions.contains("PMDD") }

    /// Eating-disorder history: no calories, step counts or exercise targets.
    var hidesActivityNumbers: Bool { store.data.conditions.contains("Eating-disorder history") }
}

/// Where today falls in a pill, ring or patch pack.
struct PackPosition: Hashable {
    var day: Int
    var activeDays: Int
    var packLength: Int
    /// Midnight of the app day `day` is counted on.
    var appDay: Date

    var hasBreak: Bool { activeDays < packLength }
    var isBreak: Bool { hasBreak && day > activeDays }

    /// "Pill" for the pill, "Day" for the ring and patch.
    static func unit(for method: BirthControl) -> String { method == .combinedPill ? "Pill" : "Day" }

    private func date(inDays days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: appDay) ?? appDay
    }

    /// The day the break week starts (nil when in it or with continuous use).
    var breakStart: Date? { hasBreak && !isBreak ? date(inDays: activeDays - day + 1) : nil }
    var newPackStart: Date { date(inDays: packLength - day + 1) }

    static func shortDate(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }

    /// "break week" for a 7-day break, "break days" for a shorter one (24+4).
    var breakName: String { packLength - activeDays >= 7 ? "break week" : "break days" }

    /// "active" or "break week" / "break days" for day `d` of this pack.
    func kind(of d: Int) -> String {
        hasBreak && d > activeDays ? breakName : "active"
    }

    func summary(unit: String) -> String {
        var parts = ["\(unit) \(day) of \(packLength)", kind(of: day)]
        if let b = breakStart {
            parts.append("\(breakName) starts \(Self.shortDate(b))")
        } else if isBreak {
            parts.append("new pack starts \(Self.shortDate(newPackStart))")
        } else {
            parts.append("no break week \u{00B7} next pack \(Self.shortDate(newPackStart))")
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
