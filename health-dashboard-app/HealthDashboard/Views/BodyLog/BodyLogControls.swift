import SwiftUI
import HealthCore

// Controls shared by Settings, onboarding, the Cycle screen and the Body tab:
// where she is in her pill pack, her bedtime and up-by time, and the 988
// crisis line.

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
        case (_, true): kind = p.packLength - p.activeDays >= 7 ? "break" : "placebo"
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
            default: return "21 active pills, then 7 days of placebo pills or no pills."
            }
        case .extended: return "24 active pills, then 4 placebo pills (break days)."
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

    private var skipMessage: String {
        let start = model.packState.flatMap { $0.isBreak ? Date.now : model.nextBreakStart }
        let when = start.map { PackPosition.shortDate($0) } ?? "the first break day"
        return "Your next \(method == .combinedPill ? "pack" : model.packThing) starts on \(when) instead of taking the break, so no withdrawal bleed is due this time. This changes only this pack. Skipping the break is fine for most combined pills, rings and patches; if your pack has pills in more than one color, ask a pharmacist which to take."
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
            .accessibilityHint("Starts your next pack where the break would begin")
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
            return "Your bedtime comes after your up-by time. A bedtime from noon on counts as the evening before, and before noon as after midnight, so check both times."
        }
        let need = model.sleepNeed.minutes
        let base = "That\u{2019}s \(Clock.duration(inBed)) in bed, from bedtime to up-by."
        if inBed > 14 * 60 {
            return base + " That\u{2019}s a lot. Check that bedtime and up-by are both right."
        }
        if inBed + 15 < need {
            return base + " Shorter than your sleep need of about \(Clock.duration(need)), so you\u{2019}d build sleep debt."
        }
        return base + " Enough for your sleep need of about \(Clock.duration(need))."
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 8) {
            row(title: "Bedtime", detail: "When you plan to be in bed", selection: bedtimeBinding)
            Divider().overlay(p.cardBorder)
            row(title: "Up by", detail: "The latest you can get up. The smart alarm never goes later.", selection: upByBinding)
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

// MARK: - 988

/// The 988 Suicide & Crisis Lifeline (US), shown on the Body and Cycle
/// screens when PMDD is added. Calls and texts go straight from the phone.
/// She can shrink it to one line; the choice is remembered on this phone.
struct CrisisLineCard: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("crisisLineCompact") private var compact = false

    private static let call = URL(string: "tel:988")!
    private static let text = URL(string: "sms:988")!

    var body: some View {
        if compact { compactCard } else { fullCard }
    }

    private var fullCard: some View {
        Card(accent: .pink) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.pink.ink(scheme))
                    .frame(width: 36, height: 36)
                    .background(Accent.pink.fill(scheme).opacity(0.2), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("988 Suicide & Crisis Lifeline \u{00B7} call or text 988")
                        .font(.scaled(size: 15, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Free and confidential, any time, if your mood gets very low or you think about hurting yourself. 988 works in the US; elsewhere, call your local emergency number.")
                        .font(.scaled(size: 13)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                link("Call 988", systemImage: "phone.fill", url: Self.call)
                link("Text 988", systemImage: "message.fill", url: Self.text)
            }
            Button("Show as one line") { compact = true }
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(Palette(scheme: scheme).secondary)
                .frame(minHeight: 44)
                .accessibilityHint("Keeps the 988 line here in a smaller form")
        }
    }

    private var compactCard: some View {
        let p = Palette(scheme: scheme)
        return HStack(spacing: 10) {
            Button { compact = false } label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(Accent.pink.ink(scheme))
                        .accessibilityHidden(true)
                    Text("988 Lifeline (US) \u{00B7} call or text")
                        .font(.scaled(size: 14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("988 Suicide and Crisis Lifeline, US. Show more")
            Link(destination: Self.call) {
                Image(systemName: "phone.fill").font(.scaled(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(onFill)
                    .background(fill, in: Circle())
            }
            .accessibilityLabel("Call 988")
            Link(destination: Self.text) {
                Image(systemName: "message.fill").font(.scaled(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(onFill)
                    .background(fill, in: Circle())
            }
            .accessibilityLabel("Text 988")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Accent.pink.tint(scheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(p.cardBorder))
    }

    /// Filled buttons: white on the deep pink (5.4:1) in light mode, near
    /// black on the bright pink (7:1) in dark mode.
    private var fill: Color { scheme == .dark ? Accent.pink.fill(.dark) : Accent.pink.ink(.light) }
    private var onFill: Color { scheme == .dark ? Color(hex: 0x1A0E00) : .white }

    private func link(_ title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            Label(title, systemImage: systemImage)
                .font(.scaled(size: 15, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(onFill)
                .background(fill, in: Capsule())
        }
        .accessibilityLabel(title)
    }
}
