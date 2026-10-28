import SwiftUI
import HealthCore

// Controls shared by Settings, onboarding, the Cycle screen and the Body tab:
// where she is in her pill pack, and her bedtime and up-by time.

// MARK: - Your pack

/// Pack type (21 + 7, 24 + 4, continuous) and "Today is pill __", with a
/// summary line under it: "Pill 9 of 28 · active · break week starts Mon, Nov 9".
/// For the combined pill, ring and patch.
struct PackSetupControl: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    enum PackType: Hashable, CaseIterable {
        case standard, extended, continuous

        var activeDays: Int {
            switch self {
            case .standard: return 21
            case .extended: return 24
            case .continuous: return 28
            }
        }

        func title(for method: BirthControl) -> String {
            switch self {
            case .standard: return method == .combinedPill ? "21 + 7" : "3 weeks + 1 off"
            case .extended: return "24 + 4"
            case .continuous: return "Continuous"
            }
        }

        /// 24 + 4 packs only exist for the pill.
        static func options(for method: BirthControl) -> [PackType] {
            method == .combinedPill ? allCases : [.standard, .continuous]
        }

        static func from(activeDays: Int) -> PackType {
            switch activeDays {
            case 24: return .extended
            case 28...: return .continuous
            default: return .standard
            }
        }
    }

    private var method: BirthControl { model.packMethod ?? .combinedPill }
    private var length: Int { max(store.data.packLength, 1) }
    private var unit: String { PackPosition.unit(for: method) }

    private var typeBinding: Binding<PackType> {
        // Keeps the day she started this pack, so the pill she's on stays put.
        Binding(get: { PackType.from(activeDays: store.data.packActiveDays) },
                set: { type in model.setPackType(activeDays: type.activeDays, packLength: 28) })
    }

    private var dayBinding: Binding<Int> {
        Binding(get: { model.packDay ?? 0 },
                set: { day in if day > 0 { model.setPackDay(day) } })
    }

    private func dayLabel(_ d: Int) -> String {
        let p = model.packPosition(day: d)
        let kind: String
        switch (method, p.hasBreak && d > p.activeDays) {
        case (.ring, true): kind = "ring-free"
        case (.patch, true): kind = "patch-free"
        // One label for every pack: "break" (21 + 7 and 24 + 4 alike). The
        // type note says break days may be placebo pills or no pills.
        case (_, true): kind = "break"
        default: kind = "active"
        }
        return "\(unit) \(d) \u{00B7} \(kind)"
    }

    private var typeNote: String {
        switch PackType.from(activeDays: store.data.packActiveDays) {
        case .standard:
            switch method {
            case .ring: return "3 weeks with the ring in, then a ring-free week."
            case .patch: return "A new patch each week for 3 weeks, then a patch-free week."
            default: return "21 active pills, then 7 break days (placebo pills or no pills)."
            }
        case .extended: return "24 active pills, then 4 break days (placebo pills)."
        case .continuous:
            switch method {
            case .ring: return "A new ring straight away each time, with no ring-free week, so no withdrawal bleed is expected."
            case .patch: return "A new patch every week with no patch-free week, so no withdrawal bleed is expected."
            default: return "Active pills every day, no break, so no withdrawal bleed is expected."
            }
        }
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("Pack type").font(.scaled(size: 15, weight: .bold))
                InfoButton(topic: .pillPack).padding(.vertical, -12)
                Spacer(minLength: 0)
            }
            // Segments shrink their text instead of clipping at large sizes.
            AdaptiveSegmentedPicker("Pack type", selection: typeBinding, options: PackType.options(for: method)) { t in
                t.title(for: method)
            }
            .frame(maxWidth: .infinity)
            .minimumScaleFactor(0.6)
            Text(typeNote).font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(p.cardBorder)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    dayTitle
                    Spacer(minLength: 8)
                    dayPicker
                }
                VStack(alignment: .leading, spacing: 4) {
                    dayTitle
                    dayPicker
                }
            }
            .frame(minHeight: 44)
            summary
            if showsSkip { skipRow }
        }
        .confirmationDialog("Skip this break?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Skip the break") { model.skipThisBreak() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(skipMessage)
        }
    }

    /// Settings and the Cycle screen offer "Skip this break"; onboarding doesn't.
    var showsSkip = true
    @State private var confirmSkip = false

    private var dayTitle: some View {
        Text(unit == "Pill" ? "Today is pill" : "Today is day").font(.scaled(size: 15, weight: .bold))
    }

    private var dayPicker: some View {
        Picker(unit == "Pill" ? "Today is pill" : "Today is day", selection: dayBinding) {
            if model.packDay == nil { Text("Choose\u{2026}").tag(0) }
            ForEach(1...length, id: \.self) { d in
                Text(dayLabel(d)).tag(d)
            }
        }
        .pickerStyle(.menu)
        .tint(Accent.indigo.ink(scheme))
    }

    private var packWord: String { method == .combinedPill ? "pack" : model.packThing }

    /// What "Skip this break" does today: from the break's first day, or,
    /// when she's already in the break, from today (the rest is left out).
    private var skipWhatItDoes: String {
        if model.packState?.isBreak == true {
            return "You\u{2019}re in your break now. Skipping it means you start your next \(packWord) today and leave out the rest of the break. A bleed that has already started may carry on for a few days."
        }
        let when = model.nextBreakStart.map { PackPosition.shortDate($0) } ?? "the first break day"
        return "Skipping means you start your next \(packWord) on \(when) instead of taking the break, so no withdrawal bleed is due this time. Some spotting is common."
    }

    /// Who skipping is for, shown next to the button and in the confirmation.
    private var skipOnePhaseNote: String {
        method == .combinedPill
            ? "Only for one-phase packs (all active pills the same color). Ask a pharmacist if yours has several colors."
            : "Fine for most rings and patches. If you\u{2019}re not sure, ask a pharmacist first."
    }

    /// The same pregnancy caveat as the Cycle screen.
    private var skipPregnancyNote: String { CycleCare.noBleedAdvice(method) }

    private var skipMessage: String {
        "\(skipWhatItDoes) This changes only this \(packWord). \(skipOnePhaseNote)"
    }

    @ViewBuilder
    private var skipRow: some View {
        if model.packSkippingBreak {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("You\u{2019}re skipping this break.")
                    .font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Undo") { model.undoSkipBreak() }
                    .font(.scaled(size: 14, weight: .bold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minHeight: 44)
            }
        } else if model.canSkipThisBreak {
            Button { confirmSkip = true } label: {
                Label("Skip this break", systemImage: "forward.end.fill")
                    .font(.scaled(size: 14, weight: .bold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint(model.packState?.isBreak == true
                               ? "Starts your next pack today and leaves out the rest of the break"
                               : "Starts your next pack where the break would begin")
            VStack(alignment: .leading, spacing: 6) {
                Text(skipWhatItDoes)
                Text(skipOnePhaseNote)
                Text(skipPregnancyNote)
            }
            .font(.scaled(size: 13)).secondaryText()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let line = model.packSummaryLineShown {
            Text(line)
                .font(.scaled(size: 14, weight: .semibold))
                .foregroundStyle(Accent.indigo.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if model.packDayIsEstimated, let day = model.packDay {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("A guess from your last logged bleed. Check it against your pack.")
                        .font(.scaled(size: 13)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("That\u{2019}s right") { model.setPackDay(day) }
                        .font(.scaled(size: 14, weight: .bold))
                        .foregroundStyle(Accent.indigo.ink(scheme))
                        .frame(minHeight: 44)
                }
            } else {
                Text("Moves on by itself every day, into your next \(method == .combinedPill ? "pack" : "cycle") too. The app checks with you when a new one should have started.")
                    .font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Not set yet. Pick today\u{2019}s \(unit == "Pill" ? "pill" : "day") from your pack so the break lands on the right days.")
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pack checks

/// The pack questions the app asks on its own: "Did you start your new pack
/// on Mon, Nov 9?" after it rolled her into a new pack, and "Bleeding on
/// active pills?" when a logged bleed doesn't fit her pack day. Shows
/// nothing when there's nothing to ask.
struct PackCheckCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var pickingDate = false
    @State private var picked = Date.now
    @State private var checkingDay = false

    var body: some View {
        if model.packNeedsCheck, let date = model.packCheckNewPackDate {
            newPackCard(date)
        } else if model.packBleedOutsideBreak, let bleed = model.packBleedOutsideBreakDate {
            bleedCard(bleed)
        }
    }

    private var cal: Calendar { Calendar.current }

    private func dayText(_ date: Date) -> String {
        if cal.isDateInToday(date) { return "today" }
        if cal.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// Whole days `picked` falls after the day the new pack was due.
    private func daysLate(_ picked: Date, after due: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: due), to: cal.startOfDay(for: picked)).day ?? 0
    }

    private var pickRange: ClosedRange<Date> {
        let today = cal.startOfDay(for: .now)
        let from = cal.date(byAdding: .day, value: -(max(store.data.packLength, 1) + 7), to: today) ?? today
        return from...Date.now
    }

    private func newPackCard(_ date: Date) -> some View {
        Card(accent: .indigo) {
            Label("New \(model.packThing == "pill" ? "pack" : model.packThing)?", systemImage: "pills.fill")
                .font(.scaled(size: 17, weight: .bold))
                .foregroundStyle(Accent.indigo.ink(scheme))
                .accessibilityAddTraits(.isHeader)
            Text("Did you \(model.newPackPhrase) \(dayText(date))? The app moved you on to a new one then. A yes keeps your break \(model.packThing == "pill" ? "and pill days" : "days") lined up.")
                .font(.scaled(size: 15))
                .fixedSize(horizontal: false, vertical: true)
            if pickingDate {
                DatePicker("Day I started", selection: $picked, in: pickRange, displayedComponents: .date)
                    .font(.scaled(size: 15, weight: .semibold))
                    .tint(Accent.indigo.ink(scheme))
                    .frame(minHeight: 44)
                // 2 or more days late counts as missed pills (Okafor B).
                if daysLate(picked, after: date) >= 2, let method = model.packMethod {
                    Label(CycleCare.lateStartWarning(method), systemImage: "exclamationmark.circle.fill")
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(Accent.coral.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    filledButton("Save") { model.setPackStart(picked); pickingDate = false }
                    plainButton("Cancel") { pickingDate = false }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { answerButtons(date) }
                    VStack(spacing: 8) { answerButtons(date) }
                }
                plainButton("Not now") { model.dismissPackCheck() }
            }
        }
    }

    @ViewBuilder
    private func answerButtons(_ date: Date) -> some View {
        filledButton("Yes") { model.confirmNewPack() }
        plainButton("I started on\u{2026}") {
            picked = date
            pickingDate = true
        }
    }

    private func bleedCard(_ bleed: Date) -> some View {
        Card(accent: .coral) {
            Label("Bleeding on active \(model.packThing == "pill" ? "pills" : "days")?", systemImage: "drop.fill")
                .font(.scaled(size: 17, weight: .bold))
                .foregroundStyle(Accent.coral.ink(scheme))
                .accessibilityAddTraits(.isHeader)
            Text(bleedText(bleed))
                .font(.scaled(size: 15))
                .fixedSize(horizontal: false, vertical: true)
            if checkingDay {
                PackSetupControl(showsSkip: false)
                filledButton("Done") {
                    checkingDay = false
                    model.dismissPackCheck()
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { bleedButtons }
                    VStack(spacing: 8) { bleedButtons }
                }
            }
        }
    }

    @ViewBuilder
    private var bleedButtons: some View {
        filledButton("Check my pack day") { checkingDay = true }
        plainButton("It\u{2019}s right") { model.dismissPackCheck() }
    }

    private func bleedText(_ bleed: Date) -> String {
        let which = model.packDay(on: bleed).map { model.packThing == "pill" ? "pill \($0)" : "day \($0) of your pack" } ?? "an active day"
        return "You logged bleeding \(dayText(bleed)), on \(which). If the app has your pack day wrong, your break is on the wrong days. Spotting on active \(model.packThing == "pill" ? "pills" : "days") is also common, especially in the first few months, or after a late or missed one."
    }

    private func filledButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.scaled(size: 15, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 10)
                .foregroundStyle(scheme == .dark ? Color(hex: 0x0E1136) : .white)
                .background(scheme == .dark ? Accent.indigo.fill(.dark) : Accent.indigo.ink(.light), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func plainButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.scaled(size: 15, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 10)
                .foregroundStyle(Accent.indigo.ink(scheme))
                .background(Accent.indigo.fill(scheme).opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bedtime and up-by

/// Bedtime and the latest time she has to be up, any time of day. These
/// drive the caffeine cutoff, the wake plan, the smart alarm, streaks and
/// water pace.
struct SleepScheduleControl: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    /// A wall-clock bedtime as minutes relative to the wake day, by the one
    /// rule the whole app uses (`AppDay.bedtime(fromClock:)`): noon or later
    /// is the evening before (11pm is -60), before noon is after midnight
    /// (12:30am is 30).
    static func bedtime(clock: Minutes) -> Minutes { AppDay.bedtime(fromClock: clock) }

    private func date(_ minutes: Minutes) -> Date {
        let m = ((minutes % 1440) + 1440) % 1440
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
    }

    private var bedtimeBinding: Binding<Date> {
        Binding(get: { date(store.data.bedtime) },
                set: { store.data.bedtime = Self.bedtime(clock: Clock.minutesOfDay($0)) })
    }

    private var upByBinding: Binding<Date> {
        Binding(get: { date(store.data.upBy) },
                set: { store.data.upBy = Clock.minutesOfDay($0) })
    }

    private var inBed: Int { AppDay.timeInBed(bedtime: store.data.bedtime, upBy: store.data.upBy) }

    private var bedAfterWake: Bool { inBed <= 0 }

    private var note: String {
        if bedAfterWake {
            return "Your bedtime comes after your latest wake-up. A bedtime from noon on counts as the evening before, and before noon as after midnight, so check both times."
        }
        let need = model.sleepNeed.minutes
        if inBed > 14 * 60 {
            return "That\u{2019}s \(Clock.duration(inBed)) in bed. That\u{2019}s a lot. Check that both times are right."
        }
        // Time asleep (in bed minus the time it takes to drift off), against
        // the need, as Today counts it. Exact, with no slack: "enough" next
        // to a need 7 min higher read as a contradiction (Dubois 2).
        let asleep = max(inBed - AppModel.planLatency, 0)
        let gap = need - asleep
        let compared: String
        if gap > 0 {
            compared = "\(Clock.duration(gap)) under your usual need of \(Clock.duration(need))."
        } else if gap < 0 {
            compared = "\(Clock.duration(-gap)) over your usual need of \(Clock.duration(need))."
        } else {
            compared = "right at your usual need of \(Clock.duration(need))."
        }
        let tonight = model.tonightPlan.need
        let tonightNote = tonight > need + 5
            ? " Tonight you need \(Clock.duration(tonight)); Today shows when to go to bed."
            : ""
        return "That\u{2019}s \(Clock.duration(inBed)) in bed, about \(Clock.duration(asleep)) asleep: " + compared + tonightNote
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 8) {
            row(title: "Bedtime", detail: "When you plan to be in bed", selection: bedtimeBinding)
            Divider().overlay(p.cardBorder)
            row(title: "Latest wake-up", detail: "The latest you can get up. The smart alarm never goes later.", selection: upByBinding)
            if bedAfterWake {
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(note).font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(title: String, detail: String, selection: Binding<Date>) -> some View {
        LabeledControlRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(size: 15, weight: .bold))
                Text(detail).font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        } control: {
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(Accent.purple.ink(scheme))
                .timePickerAccessibility(title, time: selection.wrappedValue)
        }
        .frame(minHeight: 44)
    }
}
