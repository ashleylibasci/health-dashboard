import SwiftUI
import HealthCore

// Small pieces shared by the Body, Log, Caffeine, Settings, Conditions,
// Cycle and onboarding screens.

/// Display names, symbols and colors for drinks and cycle phases.
enum BodyLogStyle {
    static func symbol(for icon: Drink.Icon) -> String {
        switch icon {
        case .latte: "mug.fill"
        case .iced: "takeoutbag.and.cup.and.straw.fill"
        case .tea: "leaf.fill"
        case .can: "bolt.fill"
        case .shot: "cup.and.saucer.fill"
        }
    }

    static func accent(for icon: Drink.Icon) -> Accent {
        switch icon {
        case .latte: .yellow
        case .iced: .orange
        case .tea: .mint
        case .can: .blue
        case .shot: .purple
        }
    }

    static func name(for icon: Drink.Icon) -> String {
        switch icon {
        case .latte: "Hot cup"
        case .iced: "Iced cup"
        case .tea: "Tea"
        case .can: "Can"
        case .shot: "Espresso shot"
        }
    }

    static func phaseName(_ phase: CyclePhase) -> String {
        switch phase {
        case .period: "Period"
        case .follicular: "Follicular"
        case .ovulation: "Ovulation"
        case .luteal: "Luteal"
        case .unknown: "Unknown"
        }
    }

    /// Phase name hedged for birth control: on the mini pill ovulation may
    /// or may not happen, so the middle of the cycle is just "Mid-cycle".
    static func phaseName(_ phase: CyclePhase, birthControl: BirthControl?) -> String {
        if phase == .ovulation, let bc = birthControl, bc.ovulation == .sometimes { return "Mid-cycle" }
        return phaseName(phase)
    }

    /// Text and icon color for a phase. Each phase has its own hue:
    /// period coral, follicular mint, ovulation yellow, luteal purple.
    static func phaseAccent(_ phase: CyclePhase) -> Accent {
        switch phase {
        case .period: .coral
        case .follicular: .mint
        case .ovulation: .yellow
        case .luteal: .purple
        case .unknown: .indigo
        }
    }

    /// Fill for calendar days, timelines and legends.
    ///
    /// Light mode: every phase is at least 3:1 against the white card and the
    /// page background. Period and follicular (red vs green, the pair
    /// color-blind eyes mix up) also differ a lot in lightness: period is
    /// dark, follicular mid. Dark mode: period mid, follicular light. Every
    /// calendar day also carries the phase letter (`phaseLetter`), so color
    /// is never the only cue.
    static func phaseFill(_ phase: CyclePhase, _ scheme: ColorScheme) -> Color {
        switch (phase, scheme) {
        case (.period, .dark): Color(hex: 0xE5484D)
        case (.follicular, .dark): Color(hex: 0x7BE3B8)
        case (.ovulation, .dark): Color(hex: 0xFFD24D)
        case (.luteal, .dark): Color(hex: 0x7050EE)
        case (.period, _): Color(hex: 0xAA2A20)
        case (.follicular, _): Color(hex: 0x27A267)
        case (.ovulation, _): Color(hex: 0xB08600)
        case (.luteal, _): Color(hex: 0x5B3FD0)
        case (.unknown, _): Palette(scheme: scheme).track
        }
    }

    /// Readable text on top of `phaseFill` (4.5:1 or more in both schemes).
    static func phaseOnFill(_ phase: CyclePhase, _ scheme: ColorScheme) -> Color {
        switch (phase, scheme) {
        case (.luteal, _): .white
        case (.period, .light): .white
        case (.unknown, _): Palette(scheme: scheme).primary
        default: Color(hex: 0x0B0B14)
        }
    }

    /// A one-letter cue for each phase, so the calendar doesn't rely on
    /// color alone: P, F, O (M on the mini pill), L.
    static func phaseLetter(_ phase: CyclePhase, birthControl: BirthControl? = nil) -> String {
        switch phase {
        case .period: "P"
        case .follicular: "F"
        case .ovulation: birthControl?.ovulation == .sometimes ? "M" : "O"
        case .luteal: "L"
        case .unknown: ""
        }
    }

    /// Pill pack colors: active days and the break week (withdrawal bleed).
    static func packFill(isBreak: Bool, _ scheme: ColorScheme) -> Color {
        isBreak ? phaseFill(.period, scheme) : Accent.indigo.fill(scheme)
    }

    /// "Tuesday, Oct 20" in upper case, for the tab screens' date line.
    static var todayLine: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }

    /// "2pm" instead of "2:00pm" for chart ticks and short labels.
    static func shortTime(_ minutes: Minutes) -> String {
        Clock.format(minutes).replacingOccurrences(of: ":00", with: "")
    }
}

/// The health conditions the app adapts to, with what each one changes.
enum ConditionCatalog {
    struct Item: Identifiable, Hashable {
        let name: String
        /// Exactly what adding it changes in the app, nothing more.
        let change: String
        /// What the condition is, in one or two plain sentences.
        let meaning: String
        var id: String { name }
    }

    static let all: [Item] = [
        Item(name: "PCOS",
             change: "Counts days since your last period instead of predicting the next one: no countdowns and no \u{201C}late period\u{201D} wording. Adds \u{201C}Hair changes\u{201D} to the symptom log.",
             meaning: "Polycystic ovary syndrome, a common hormone condition. Ovulation can be late or skipped, so periods can be far apart or unpredictable."),
        Item(name: "Endometriosis",
             change: "Saved for your own reference; nothing else changes yet. Log pain, cramps and bleeding on the Cycle screen.",
             meaning: "Tissue like the lining of the uterus grows elsewhere, which can cause painful periods and pelvic pain."),
        Item(name: "PMDD",
             change: "Keeps the 988 Suicide & Crisis Lifeline (call or text 988) on the Body and Cycle screens.",
             meaning: "Premenstrual dysphoric disorder: severe mood changes, such as depression, anxiety or irritability, in the week or two before a period."),
        Item(name: "Thyroid condition",
             change: "Saved for your own reference; nothing else changes. Your usual heart rate and HRV already follow your last 30 days, so they catch up after a dose change.",
             meaning: "An over- or underactive thyroid changes your energy, heart rate and sleep."),
        Item(name: "Iron-deficiency anemia",
             change: "Saved for your own reference; nothing else changes yet. Logging heavy flow and tiredness keeps a history you can show your doctor.",
             meaning: "Too little iron to make enough red blood cells, often from heavy periods. It can make you tired and short of breath."),
        Item(name: "Heavy periods / fibroids",
             change: "Saved for your own reference; nothing else changes. Logging a heavy day shows when-to-get-care signs.",
             meaning: "Fibroids are non-cancerous growths in the uterus. They and other causes can make periods heavy or long."),
        Item(name: "Menstrual migraine",
             change: "Saved for your own reference; nothing else changes yet. Log headaches on the Cycle screen to keep them by date.",
             meaning: "Migraines that come around your period, often from the drop in estrogen."),
        Item(name: "Perimenopause",
             change: "Saved for your own reference; nothing else changes. If your cycle has become unpredictable, choose \u{201C}Irregular or not sure\u{201D} in Settings to turn off countdowns.",
             meaning: "The years before menopause, when cycles get irregular and hot flashes and poor sleep are common."),
        Item(name: "Eating-disorder history",
             change: "Hides calories, step counts, exercise targets and your water goal everywhere, whatever the calories setting says. Shows where to find support.",
             meaning: "A past or current eating disorder. Numbers about food and exercise can be unhelpful, so the app leaves them out."),
    ]

    static func change(for name: String) -> String? { all.first { $0.name == name }?.change }
}

/// The small "Custom" pill on drinks she made herself.
struct CustomDrinkBadge: View {
    var accent: Accent
    @Environment(\.colorScheme) private var scheme

    init(accent: Accent = .orange) { self.accent = accent }

    var body: some View {
        Text("CUSTOM")
            .font(.scaled(size: 11, weight: .bold))
            .tracking(0.3)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(accent.ink(scheme))
            .background(accent.fill(scheme).opacity(0.24), in: Capsule())
    }
}

/// A drink in "My drinks": icon, name, size, caffeine. `featured` is the
/// filled yellow style used for her usual drink.
struct SavedDrinkRow: View {
    var drink: Drink
    var featured: Bool
    var trailingSystemImage: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    init(drink: Drink, featured: Bool = false, trailingSystemImage: String? = "plus") {
        self.drink = drink
        self.featured = featured
        self.trailingSystemImage = trailingSystemImage
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        let accent = BodyLogStyle.accent(for: drink.icon)
        let ink: Color = featured ? Color(hex: 0x1A1400) : p.primary
        let sub: Color = featured ? Color(hex: 0x1A1400, alpha: 0.78) : p.secondary
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        // At accessibility sizes the row stacks (no icon, mg under the name),
        // so "Latte" never breaks into letters (round 3, A1).
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            if !typeSize.isAccessibilitySize {
                Image(systemName: BodyLogStyle.symbol(for: drink.icon))
                    .font(.scaled(size: 17, weight: .semibold))
                    .foregroundStyle(featured ? ink : accent.ink(scheme))
                    .frame(width: 40, height: 40)
                    .background(featured ? Color.black.opacity(0.12) : accent.fill(scheme).opacity(0.24), in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(drink.name)
                    .font(.scaled(size: 15, weight: .bold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let size = drink.sizeLabel {
                        Text(size).font(.scaled(size: 13, weight: .semibold)).foregroundStyle(sub)
                    }
                    if drink.isCustom { CustomDrinkBadge() }
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            HStack(spacing: 12) {
                Text("\(drink.caffeineMg) mg").font(.scaledNumber(17)).lineLimit(1).fixedSize()
                if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.scaled(size: 15, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(featured ? Accent.yellow.fill(scheme) : accent.tint(scheme), in: shape)
        .overlay(shape.strokeBorder(featured ? Color.clear : accent.fill(scheme).opacity(0.24)))
        .contentShape(shape)
    }
}

/// A settings-style toggle with an optional icon and a detail line.
struct SettingToggleRow: View {
    var title: String
    var detail: String?
    var systemImage: String?
    var accent: Accent
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme

    init(title: String, detail: String? = nil, systemImage: String? = nil, accent: Accent = .mint, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.accent = accent
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.scaled(size: 15, weight: .semibold))
                        .foregroundStyle(accent.ink(scheme))
                        .frame(width: 36, height: 36)
                        .background(accent.tint(scheme), in: Circle())
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.scaled(size: 15, weight: .bold))
                    if let detail {
                        Text(detail).font(.scaled(size: 13)).secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(Accent.mint.fill(scheme))
        .frame(minHeight: 44)
        .padding(.vertical, 6)
    }
}

/// The big heading used at the top of the Body and Log tabs.
struct BodyLogTabHeader: View {
    var title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(BodyLogStyle.todayLine)
                .font(.scaled(size: 13, weight: .semibold))
                .tracking(0.3)
                .secondaryText()
            Text(title)
                .font(.scaled(size: 34, weight: .bold))
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 4)
    }
}

// MARK: - Cycle copy

/// What each part of the cycle (or pill pack) typically means for energy,
/// sleep and mood, in plain words. Used by the scrubbable cycle charts and
/// the "How your cycle affects you" screen.
enum CycleCopy {
    struct Effects: Hashable {
        var energy: String
        var sleep: String
        var mood: String
        var hrv: String
        var restingHR: String
        var exercise: String
    }

    /// The days each phase covers for a cycle of `length` days.
    static func range(_ phase: CyclePhase, length: Int, periodLength: Int = CycleEstimator.typicalPeriodLength) -> ClosedRange<Int> {
        let len = max(length, 21)
        let ovulation = len - 14
        let bleed = max(periodLength, 1)
        switch phase {
        case .period: return 1...bleed
        case .follicular: return (bleed + 1)...max(bleed + 1, ovulation - 2)
        case .ovulation: return (ovulation - 1)...(ovulation + 1)
        case .luteal: return (ovulation + 2)...len
        case .unknown: return 1...len
        }
    }

    static func effects(_ phase: CyclePhase) -> Effects {
        switch phase {
        case .period:
            return Effects(energy: "Often lower on the first heavy days, then picks up.",
                           sleep: "You may need a little more. Cramps can wake you on day 1 or 2.",
                           mood: "Can feel low or tired at first; usually lifts as bleeding eases.",
                           hrv: "Starts climbing back toward your usual.",
                           restingHR: "Drops back toward your usual.",
                           exercise: "Gentle movement can ease cramps. Go by feel.")
        case .follicular:
            return Effects(energy: "Rising. Often your best-feeling stretch of the month.",
                           sleep: "Usually deepest and most refreshing.",
                           mood: "Often upbeat, social and motivated.",
                           hrv: "Often at its highest.",
                           restingHR: "Often at its lowest.",
                           exercise: "A great week for hard workouts and trying for personal bests.")
        case .ovulation:
            return Effects(energy: "Many people feel a small lift or peak.",
                           sleep: "Usually steady.",
                           mood: "Often confident. Some feel a one-sided twinge low in the belly.",
                           hrv: "Steady, then starts to dip afterward.",
                           restingHR: "Starts rising a little afterward.",
                           exercise: "Still a strong time to train. Warm up well.")
        case .luteal:
            return Effects(energy: "Steady at first, then often dips in the last week before your period.",
                           sleep: "Warmer nights and lighter sleep; you may wake more. You need a bit more sleep.",
                           mood: "Late in this phase, irritability, anxiety or low mood (PMS) are common.",
                           hrv: "A few points lower than usual. That's expected, not a problem.",
                           restingHR: "A few beats higher than usual. Also expected.",
                           exercise: "Steady workouts feel better than all-out efforts. Hydrate more.")
        case .unknown:
            return Effects(energy: "", sleep: "", mood: "", hrv: "", restingHR: "", exercise: "")
        }
    }

    /// Pill, ring or patch: active weeks hold hormones level; the break week
    /// brings a withdrawal bleed.
    static func packEffects(isBreak: Bool) -> Effects {
        isBreak
            ? Effects(energy: "Some people feel a little more tired in the break week.",
                      sleep: "Usually unchanged. Cramps on bleed days can wake you.",
                      mood: "Some notice headaches or low mood when the hormones pause.",
                      hrv: "Usually close to your usual.",
                      restingHR: "Usually close to your usual.",
                      exercise: "Train as normal; go easier if you have cramps or a headache.")
            : Effects(energy: "Usually steady. The hormones are held level, so there's no monthly peak or dip.",
                      sleep: "Usually steady from week to week.",
                      mood: "Steady for most people. If your mood is often low, tell your doctor.",
                      hrv: "Swings less across the month than in a natural cycle.",
                      restingHR: "Swings less across the month than in a natural cycle.",
                      exercise: "Train as normal. There's no best or worst week to plan around.")
    }

    /// The readout for one day of a natural cycle.
    static func dayReadout(day: Int, length: Int, birthControl: BirthControl?, isToday: Bool,
                           periodLength: Int = CycleEstimator.typicalPeriodLength) -> CycleReadout {
        let phase = CycleEstimator.phase(day: day, length: length, periodLength: periodLength)
        let e = effects(phase)
        let late = CycleEstimator.isLateLuteal(day: day, length: length)
        var name = BodyLogStyle.phaseName(phase, birthControl: birthControl)
        if phase == .luteal { name = late ? "Late luteal" : "Early luteal" }
        let energy = phase == .luteal && !late ? "Steady." : e.energy
        let mood = phase == .luteal && !late ? "Usually steady." : e.mood
        var detail = "Energy: \(energy)\nSleep: \(e.sleep)\nMood: \(mood)"
        if phase == .ovulation, birthControl?.ovulation == .sometimes {
            detail = "On the mini pill you may or may not release an egg this cycle, so this is a rough guide.\n" + detail
        }
        return CycleReadout(title: isToday ? "Today \u{00B7} day \(day)" : "Day \(day) of ~\(length)",
                            value: name, detail: detail, accent: BodyLogStyle.phaseAccent(phase))
    }

    /// The readout for one day of a pill pack. `activeName` / `breakName`
    /// follow her method and pack ("Active pills", "Ring in"; "Break week",
    /// "Break days" for a 24 + 4 pack).
    static func packReadout(day: Int, activeDays: Int, packLength: Int, isToday: Bool,
                            activeName: String = "Active", breakName: String? = nil) -> CycleReadout {
        let isBreak = activeDays < packLength && day > activeDays
        let e = packEffects(isBreak: isBreak)
        let breakTitle = breakName ?? (packLength - activeDays >= 7 ? "Break week" : "Break days")
        let value: String
        if isBreak {
            value = "\(breakTitle) \u{00B7} withdrawal bleed"
        } else if activeDays >= packLength {
            value = "\(activeName) \u{00B7} continuous"
        } else {
            value = "\(activeName) \u{00B7} day \(day) of \(activeDays)"
        }
        return CycleReadout(title: isToday ? "Today \u{00B7} pack day \(day)" : "Pack day \(day) of \(packLength)",
                            value: value, detail: "Energy: \(e.energy)\nSleep: \(e.sleep)\nMood: \(e.mood)",
                            accent: isBreak ? .coral : .indigo)
    }
}

struct CycleReadout: Hashable {
    var title: String
    var value: String
    var detail: String?
    var accent: Accent
}

/// A horizontal strip of days you can drag across. The readout above shows
/// the touched day (or today) and what it usually means.
struct CycleStrip: View {
    var length: Int
    var today: Int?
    var color: (Int) -> Color
    var readout: (Int) -> CycleReadout
    var startLabel = "Day 1"
    var endLabel: String? = nil
    /// A letter for each day ("P", "F", "O", "L"; "A"/"B" for a pack). Shown
    /// once under each run of days, so color is never the only cue.
    var letter: ((Int) -> String)? = nil
    @State private var selected: Int? = nil
    @Environment(\.colorScheme) private var scheme

    private var shown: Int { selected ?? today ?? 1 }

    var body: some View {
        let r = readout(shown)
        VStack(alignment: .leading, spacing: 8) {
            ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: r.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            strip
            letterRow
            HStack {
                Text(startLabel)
                Spacer()
                Text(endLabel ?? "Day \(length)")
            }
            .font(.scaled(size: 12, weight: .semibold))
            .secondaryText()
            ScrubHint(text: "Touch and drag along the days to see each one")
        }
    }

    private var strip: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(1...max(length, 1), id: \.self) { d in
                    cell(d)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .overlay(ScrubSurface { location in
                let w = max(geo.size.width, 1)
                let d = Int((location.x / w) * CGFloat(length)) + 1
                selected = min(max(d, 1), length)
            })
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAdjustableAction { direction in
            let current = selected ?? today ?? 1
            switch direction {
            case .increment: selected = min(current + 1, length)
            case .decrement: selected = max(current - 1, 1)
            @unknown default: break
            }
        }
    }

    private struct Segment: Identifiable {
        var start: Int
        var end: Int
        var letter: String
        var id: Int { start }
    }

    /// Runs of days that share a letter.
    private var segments: [Segment] {
        guard let letter else { return [] }
        var out: [Segment] = []
        for d in 1...max(length, 1) {
            let l = letter(d)
            if let last = out.last, last.letter == l {
                out[out.count - 1].end = d
            } else {
                out.append(Segment(start: d, end: d, letter: l))
            }
        }
        return out.filter { !$0.letter.isEmpty }
    }

    @ViewBuilder
    private var letterRow: some View {
        if letter != nil {
            GeometryReader { geo in
                let w = geo.size.width / CGFloat(max(length, 1))
                ForEach(segments) { seg in
                    Text(seg.letter)
                        .font(.scaled(size: 12, weight: .heavy))
                        .secondaryText()
                        .position(x: (CGFloat(seg.start - 1) + CGFloat(seg.end - seg.start + 1) / 2) * w,
                                  y: geo.size.height / 2)
                }
            }
            .frame(height: Font.scaledSize(16))
            .accessibilityHidden(true)
        }
    }

    private func cell(_ d: Int) -> some View {
        let isShown = d == shown
        let isToday = d == today
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color(d))
            .opacity(selected == nil || isShown ? 1 : 0.4)
            .frame(height: isShown ? 40 : 26)
            .overlay(alignment: .top) {
                if isToday {
                    Circle().fill(Palette(scheme: scheme).primary).frame(width: 5, height: 5).offset(y: -8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accessibilityText: String {
        let r = readout(shown)
        return "\(r.title), \(r.value). \(r.detail ?? ""). Swipe up or down to move a day."
    }
}

extension BodyLogStyle {
    /// Wrist temperature explained without ovulation talk when her method
    /// stops ovulation.
    static func wristTempExplanation(ovulationStopped: Bool) -> Explanation {
        guard ovulationStopped else { return Topic.wristTemp.explanation }
        return Explanation(id: "wristTempHormonal", title: "Wrist temperature",
                           meaning: "How your skin temperature during sleep compares with your usual.",
                           forYou: "On your birth control it tends to sit a little higher and stay flat through the month, which is normal. A clear rise over a night or two can mean you're fighting something off.")
    }
}
