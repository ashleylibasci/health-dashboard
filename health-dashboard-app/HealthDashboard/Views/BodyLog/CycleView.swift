import SwiftUI
import Charts
import HealthCore

/// The cycle screen. What it shows depends on `model.cycleDisplay`:
/// natural phases, a pill pack, a method that stops bleeding patterns,
/// an irregular cycle, or nothing. Methods that stop ovulation never get
/// ovulation, luteal days or a period countdown.
struct CycleView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore

    var body: some View {
        Screen(title: "Cycle", accent: .pink) {
            SampleDataBanner()
            NoPeriodCallout()
            PackCheckCard()
            if let reason = model.irregularReasonText { reasonNote(reason) }
            content
            links
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.cycleDisplay {
        case let .phases(day, length, phase):
            PhasesSection(day: day, length: length, phase: phase)
        case let .pack(day, activeDays, packLength):
            PackSection(day: day, activeDays: activeDays, packLength: packLength)
        case let .suppressed(method):
            if method.hasBreakWeek {
                PackUnknownSection(method: method)
            } else {
                SuppressedSection(method: method)
            }
        case .irregular:
            IrregularSection()
        case let .overdue(day, typical):
            OverdueSection(day: day, typicalLength: typical)
        case .notTracking:
            notTrackingCard
        }
    }

    /// "Showing the irregular view because PCOS is on" when she picked a
    /// natural cycle.
    private func reasonNote(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.secondary).fontWeight(.semibold)
            .secondaryText()
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Links

    /// Logging, the longer reading and the settings, as one card of rows.
    private var links: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading(model.usesPackWording ? "More about your pack" : "More about your cycle")
            RowCard {
                if store.data.cycleSetup != .notTracking {
                    MetricRow(title: "Log bleeding and symptoms", note: "Flow, cramps, headaches, mood",
                              systemImage: "drop.fill", accent: .pink) {
                        CycleLogView()
                    }
                    RowDivider()
                }
                MetricRow(title: model.usesPackWording ? "How your pack affects you" : "How your cycle affects you",
                          note: model.hidesEffortTargets ? "Energy, sleep, HRV and mood" : "Energy, sleep, HRV, mood and workouts",
                          systemImage: "waveform.path.ecg", accent: .purple) {
                    CyclePhasesView()
                }
                RowDivider()
                MetricRow(title: "Birth control and your Watch", note: birthControlSubtitle,
                          systemImage: "pills.fill", accent: .indigo) {
                    BirthControlLearnView()
                }
                if store.data.conditions.contains("PCOS") || store.data.cycleSetup == .irregular {
                    RowDivider()
                    MetricRow(title: "About PCOS", note: "What it is and what the app does differently",
                              systemImage: "heart.text.square.fill", accent: .mint) {
                        PCOSView()
                    }
                }
                RowDivider()
                MetricRow(title: "Cycle & birth control settings", note: setupSummary,
                          systemImage: "slider.horizontal.3", accent: .purple) {
                    CycleSettingsView()
                }
            }
        }
    }

    private var birthControlSubtitle: String {
        if store.birthControl != nil { return "What it does, and every method" }
        return "Every method compared"
    }

    private var setupSummary: String {
        switch store.data.cycleSetup {
        case .natural:
            switch model.irregularReason {
            case "pcos"?: return "Natural cycle \u{00B7} irregular view, because of PCOS"
            case "long"?: return "Natural cycle \u{00B7} irregular view, for long cycles"
            default: return "Natural cycle"
            }
        case .hormonal: return store.data.birthControl ?? "Birth control"
        case .irregular: return "Irregular or not sure"
        case .notTracking: return "Not tracking"
        }
    }

    private var notTrackingCard: some View {
        Card(accent: .pink) {
            Text("Cycle tracking is off").font(.cardTitle)
            Text("Cycle cards stay hidden. You can turn tracking on anytime.")
                .font(.bodyText)
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Track my cycle", accent: .pink) {
                store.data.cycleSetup = .natural
            }
        }
    }
}

// MARK: - Natural phases

/// Natural cycle (also copper IUD, hormonal IUD and the mini pill, which
/// keep or may keep ovulation): hero, scrubbable timeline, calendar and
/// next-period estimate.
private struct PhasesSection: View {
    let day: Int
    let length: Int
    let phase: CyclePhase
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        hero
        if let bc = store.birthControl { methodNote(bc) }
        timelineCard
        CycleCalendarCard()
        nextPeriodCard
        if let bc { MethodSafetyRows(method: bc) }
        CycleCareNotes()
        HowWeGotThisLink(title: "Your cycle day and phases",
                         method: "Your cycle day counts from the first day of your last period, from Apple Health and the bleeding days you log here. Your average length is the middle value of the gaps between your last 12 periods\(store.data.methodChangedDate == nil ? "" : " since your last birth-control change"). Phases are placed from that: your period (\(model.periodLength) days, \(store.data.flowLog.isEmpty ? "a typical length until you log one" : "from the bleeding you logged")), then the follicular phase, a 3-day mid-cycle estimate about 13 days before your next period, then the luteal phase (its last 7 days count as late luteal). The day you really ovulate can be several days either side, so the mid-cycle days are not your fertile days. Treat every day as an estimate.")
    }

    private var bc: BirthControl? { store.birthControl }
    private var accent: Accent { day > length ? .indigo : BodyLogStyle.phaseAccent(phase) }

    private var topic: Topic {
        switch phase {
        case .period: .period
        case .follicular: .follicular
        case .ovulation: .ovulation
        case .luteal, .unknown: .luteal
        }
    }

    /// Past her usual length (the few days before it counts as a longer
    /// cycle): "Due around now", said once, with no countdown.
    private var pastUsual: Bool { day > length }

    private var countdownText: String? {
        guard !pastUsual, let days = model.periodCountdownDays else { return nil }
        if days <= 1 { return "Period due in about a day." }
        return "Period in about \(days) days."
    }

    /// "Period", "Follicular phase", "Mid-cycle (estimate)", "Luteal phase".
    private var heroTitle: String {
        if pastUsual { return model.showsDueAroundNow ? "Due around now" : "Past your usual length" }
        switch phase {
        case .period: return "Period"
        case .ovulation: return bc?.ovulation == .sometimes ? "Mid-cycle" : "Mid-cycle (estimate)"
        default: return "\(BodyLogStyle.phaseName(phase, birthControl: bc)) phase"
        }
    }

    private var phaseNote: String {
        if pastUsual {
            if !model.showsDueAroundNow {
                return "Day \(day). Gaps between bleeds can run long on your method, so the app doesn\u{2019}t place a phase now. Log bleeding when it comes."
            }
            return "Day \(day) \u{00B7} around \(model.usualLengthPhrase(length)). Log your period when it starts. Until then the app doesn\u{2019}t place a phase or adjust for one."
        }
        switch phase {
        case .period: return "Energy can dip on heavy days. Extra sleep and iron-rich food help."
        case .follicular: return "Some people feel more energetic this week; many notice no difference."
        case .ovulation:
            return bc?.ovulation == .sometimes
                ? "On the mini pill you may or may not release an egg, so this is a rough middle-of-cycle guess."
                : "A rough estimate from your cycle length, not your fertile days. Don\u{2019}t use it to avoid pregnancy."
        case .luteal:
            return CycleEstimator.isLateLuteal(day: day, length: length)
                ? "Lower HRV and a slightly higher resting heart rate are common this week, and some people sleep more lightly. The app adds a little to tonight's sleep need."
                : "Lower HRV and a slightly higher resting heart rate are normal from now until your period."
        case .unknown: return "Log a period to see your phases."
        }
    }

    private var hero: some View {
        Card {
            AdaptiveStack(spacing: 16) {
                Ring(value: min(Double(day) / Double(max(length, 1)), 1), accent: accent,
                     label: "\(day)", caption: "Day of ~\(length)", size: 138,
                     accessibilityText: "Cycle day \(day) of about \(length)")
                VStack(alignment: .leading, spacing: 6) {
                    Text(BodyLogStyle.todayLine)
                        .font(.secondary).fontWeight(.bold)
                        .foregroundStyle(accent.ink(scheme))
                    ExplainedTitle(text: heroTitle, topic: topic, size: 22)
                    Text([countdownText, phaseNote].compactMap { $0 }.joined(separator: " "))
                        .font(.bodyText)
                        .secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func methodText(_ bc: BirthControl) -> String {
        switch bc.ovulation {
        case .sometimes:
            return "On the mini pill, some people still release an egg each cycle and some don't, and bleeding can come at unexpected times. So the phases here are a rough guide, and there's no period countdown. Late with a pill or think you could be pregnant? Take a pregnancy test."
        case .mostStill:
            return "With a hormonal IUD, most people still ovulate, so your phases apply while your periods come. Periods are often lighter or stop, so there's no period countdown. Pregnancy is very rare with an IUD, but a positive test or pregnancy symptoms need a doctor soon."
        case .natural:
            return "The copper IUD has no hormones. You ovulate normally, so your phases work like a natural cycle. Periods can be heavier."
        case .stopped:
            return bc.note
        }
    }

    private func methodNote(_ bc: BirthControl) -> some View {
        Card(accent: .indigo) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pills.fill").foregroundStyle(Accent.indigo.ink(scheme)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(bc.rawValue).font(.bodyEmphasis)
                    Text(methodText(bc))
                        .font(.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Timeline

    private struct LegendItem: Identifiable {
        let phase: CyclePhase
        var id: String { phase.rawValue }
    }

    private var timelineCard: some View {
        Card {
            ExplainedTitle(text: "Your cycle, day by day",
                           explanation: Explanation(id: "cycleTimeline", title: "Your cycle, day by day",
                                                    meaning: "Each bar is one day of your cycle, colored by phase. The dot marks today.",
                                                    forYou: "Drag along the bars to see what each day usually means for your energy, sleep and mood."), size: 17)
            CycleStrip(length: length, today: min(day, length),
                       color: { d in BodyLogStyle.phaseFill(model.cyclePhase(day: d, length: length), scheme) },
                       readout: { d in CycleCopy.dayReadout(day: d, length: length, birthControl: bc, isToday: d == day, periodLength: model.periodLength) },
                       letter: { d in BodyLogStyle.phaseLetter(model.cyclePhase(day: d, length: length), birthControl: bc) })
            legend
        }
    }

    private var legend: some View {
        let items = [CyclePhase.period, .follicular, .ovulation, .luteal].map(LegendItem.init)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                legendRow(item.phase)
            }
        }
    }

    private func legendRow(_ p: CyclePhase) -> some View {
        let r = CycleCopy.range(p, length: length, periodLength: model.periodLength)
        let t: Topic = p == .period ? .period : p == .follicular ? .follicular : p == .ovulation ? .ovulation : .luteal
        return HStack(spacing: 6) {
            Circle().fill(BodyLogStyle.phaseFill(p, scheme)).frame(width: 18, height: 18)
                .overlay(Text(BodyLogStyle.phaseLetter(p, birthControl: bc))
                    .font(.small).fontWeight(.bold)
                    .foregroundStyle(BodyLogStyle.phaseOnFill(p, scheme)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(BodyLogStyle.phaseName(p, birthControl: bc)).font(.secondary).fontWeight(.bold)
                Text("Days \(r.lowerBound)\u{2013}\(r.upperBound)").font(.small).secondaryText()
            }
            InfoButton(topic: t).padding(.vertical, -8)
        }
    }

    // MARK: Next period

    private var noCountdownText: String {
        switch bc {
        case .miniPill?:
            return "No countdown on the mini pill. Bleeding can come at unexpected times, so a date would often be wrong. Bleeding or spotting: log it if it happens, and we\u{2019}ll keep a history."
        case .hormonalIUD?:
            return "No countdown with a hormonal IUD. Periods often get lighter, irregular or stop, so a date would often be wrong. Bleeding or spotting: log it if it happens, and we\u{2019}ll keep a history."
        default:
            return "No countdowns for irregular cycles. We\u{2019}ll keep a history of your cycle lengths you can show your doctor."
        }
    }

    private var nextPeriodRange: String? {
        let cal = Calendar.current
        // As long as her own periods run (round 3, N10), not a fixed 5 days.
        guard let start = model.periodEstimateStart,
              let end = cal.date(byAdding: .day, value: max(model.periodLength, 1) - 1, to: start) else { return nil }
        let style: Date.FormatStyle = .dateTime.month(.abbreviated).day()
        return "\(start.formatted(style)) \u{2013} \(end.formatted(style))"
    }

    @ViewBuilder
    private var nextPeriodCard: some View {
        if let range = nextPeriodRange {
            Card(accent: .pink) {
                HStack {
                    SectionLabel(text: "Next period", accent: .pink)
                    Spacer()
                    InfoButton(topic: .period).padding(.vertical, -12)
                }
                Text(range).font(.numberL)
                Text(model.cycleLengthIsPersonal
                     ? "Estimated from your usual \(length)-day cycle. Real cycles vary by a few days either way."
                     : "Estimated from a typical \(length)-day cycle until you\u{2019}ve logged two periods\(store.data.methodChangedDate == nil ? "" : " since your last birth-control change"). Real cycles vary by a few days either way.")
                    .font(.bodyText)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if model.hidesPeriodCountdownOnScreens {
            Card(accent: .pink) {
                SectionLabel(text: bc == .hormonalIUD || bc == .miniPill ? "Bleeding & spotting" : "Next period", accent: .pink)
                Text(noCountdownText)
                    .font(.bodyText)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Calendar

/// This month, colored by phase. Tap a day to see what it usually means.
private struct CycleCalendarCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedDay: Int? = nil

    private struct DayCell: Identifiable {
        let id: Int
        let date: Int?
        let cycleDay: Int?
        let isToday: Bool
        let isPredicted: Bool
    }

    private var cal: Calendar { Calendar.current }
    private var todayNumber: Int { cal.component(.day, from: .now) }

    private var cells: [DayCell] {
        let today = cal.startOfDay(for: .now)
        guard let monthStart = cal.dateInterval(of: .month, for: today)?.start,
              let days = cal.range(of: .day, in: .month, for: today) else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthStart)
        let lead = (firstWeekday - cal.firstWeekday + 7) % 7
        let currentDay = model.cycleDay ?? 0
        let hidden = model.hidesPeriodCountdownOnScreens
        var out: [DayCell] = (0..<lead).map { DayCell(id: -1 - $0, date: nil, cycleDay: nil, isToday: false, isPredicted: false) }
        for d in days {
            let offset = d - todayNumber
            let nextCycle = currentDay + offset > model.cycleLength
            // No guessing into the next cycle when bleeding is unpredictable
            // (mini pill, hormonal IUD): those days stay blank.
            let cd = offset > 0 && nextCycle && hidden ? nil : model.predictedCycleDay(offset: offset)
            let isPeriod = cd.map { model.cyclePhase(day: $0, length: model.cycleLength) == .period } ?? false
            out.append(DayCell(id: d, date: d, cycleDay: cd, isToday: offset == 0,
                               isPredicted: !hidden && offset > 0 && nextCycle && isPeriod))
        }
        return out
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var readout: CycleReadout? {
        let date = selectedDay ?? todayNumber
        guard let cd = model.predictedCycleDay(offset: date - todayNumber) else { return nil }
        var r: CycleReadout
        if cd > model.cycleLength {
            r = CycleReadout(title: date == todayNumber ? "Today \u{00B7} day \(cd)" : "Day \(cd)", value: "Past \(model.cycleLengthIsPersonal ? "your usual" : "a typical") length",
                             detail: "That\u{2019}s \(model.usualLengthPhrase(model.cycleLength)). Log your period when it starts.", accent: .indigo)
        } else {
            r = CycleCopy.dayReadout(day: cd, length: model.cycleLength, birthControl: store.birthControl, isToday: date == todayNumber, periodLength: model.periodLength)
        }
        if date != todayNumber, let d = cal.date(byAdding: .day, value: date - todayNumber, to: .now) {
            r.title = "\(d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) \u{00B7} day \(cd)"
        }
        return r
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(Date.now.formatted(.dateTime.month(.wide)))
                    .font(.cardTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Tap a day").font(.secondary).fontWeight(.semibold).secondaryText()
            }
            if let r = readout {
                ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: r.accent)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.secondary).fontWeight(.bold).secondaryText()
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells) { cell in
                    if let date = cell.date {
                        Button {
                            selectedDay = selectedDay == date ? nil : date
                        } label: {
                            CycleDayCell(date: date, cycleDay: cell.cycleDay, length: model.cycleLength, birthControl: store.birthControl,
                                         isToday: cell.isToday, isPredicted: cell.isPredicted, isSelected: selectedDay == date,
                                         periodLength: model.periodLength)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(cellLabel(cell))
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            Text("Letters: P period, F follicular, M mid-cycle (estimate), L luteal.")
                .font(.secondary).fontWeight(.semibold).secondaryText()
                .accessibilityHidden(true)
            if !model.hidesPeriodCountdownOnScreens {
                HStack(spacing: 6) {
                    Circle().strokeBorder(BodyLogStyle.phaseFill(.period, scheme), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                        .frame(width: 10, height: 10)
                    Text("Dashed ring: predicted period").font(.secondary).fontWeight(.semibold).secondaryText()
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func cellLabel(_ cell: DayCell) -> String {
        guard let date = cell.date else { return "" }
        var parts = ["\(Date.now.formatted(.dateTime.month(.wide))) \(date)"]
        if cell.isToday { parts.append("today") }
        if let cd = cell.cycleDay {
            if cd > model.cycleLength {
                parts.append("cycle day \(cd), past your usual length")
            } else {
                let p = model.cyclePhase(day: cd, length: model.cycleLength)
                parts.append("cycle day \(cd), \(BodyLogStyle.phaseName(p, birthControl: store.birthControl))")
            }
        }
        if cell.isPredicted { parts.append("predicted period") }
        return parts.joined(separator: ", ")
    }
}

/// One day in the month grid, filled with its phase color.
private struct CycleDayCell: View {
    let date: Int
    let cycleDay: Int?
    let length: Int
    let birthControl: BirthControl?
    let isToday: Bool
    let isPredicted: Bool
    let isSelected: Bool
    var periodLength = CycleEstimator.typicalPeriodLength
    @Environment(\.colorScheme) private var scheme

    /// Days past her usual length get no phase (the period is due or late).
    private var phase: CyclePhase {
        guard let d = cycleDay, d <= length else { return .unknown }
        return CycleEstimator.phase(day: d, length: length, periodLength: periodLength)
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: -1) {
                Text("\(date)")
                    .font(.bodyEmphasis).fontWeight(.bold).fontDesign(.rounded)
                if !isPredicted, phase != .unknown {
                    // The phase letter, so color is never the only cue.
                    Text(BodyLogStyle.phaseLetter(phase, birthControl: birthControl))
                        .font(.small).fontWeight(.bold)
                }
            }
            .foregroundStyle(textColor)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 44)
        .frame(maxWidth: .infinity, minHeight: 40)
        .overlay {
            if isSelected { Circle().strokeBorder(Palette(scheme: scheme).primary, lineWidth: 2).padding(-2) }
        }
        .contentShape(Rectangle())
    }

    private var textColor: Color {
        if isToday { return Color(hex: 0x0B0B14) }
        if isPredicted { return BodyLogStyle.phaseAccent(.period).ink(scheme) }
        return BodyLogStyle.phaseOnFill(phase, scheme)
    }

    @ViewBuilder
    private var background: some View {
        if isToday {
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(BodyLogStyle.phaseFill(phase, scheme), lineWidth: 3).padding(-3))
        } else if isPredicted {
            Circle().strokeBorder(BodyLogStyle.phaseFill(.period, scheme), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        } else {
            Circle().fill(BodyLogStyle.phaseFill(phase, scheme))
        }
    }
}

// MARK: - Pill pack

/// Combined pill, ring or patch: pack day, active pills and break week.
/// These stop ovulation, so no phases or fertile days appear here. The
/// summary and the pack lead; setting the pack day and the safety reading
/// (missed pills, being sick, medicines…) are rows.
private struct PackSection: View {
    let day: Int
    let activeDays: Int
    let packLength: Int
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var selected: Int? = nil
    @State private var editing = false

    private var method: BirthControl { store.birthControl ?? .combinedPill }
    private var position: PackPosition { model.packPosition(day: day) }
    private var hasBreak: Bool { activeDays < packLength }
    private var isBreak: Bool { hasBreak && day > activeDays }
    private var shown: Int { selected ?? day }
    private var unit: String { PackPosition.unit(for: method).lowercased() }

    private var unitName: String {
        switch method {
        case .ring: "ring"
        case .patch: "patch"
        default: "pill"
        }
    }

    private var breakDateText: String {
        let d = position.breakStart ?? Calendar.current.startOfDay(for: .now)
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "break week" or "break days" (24 + 4).
    private var breakName: String { model.packBreakName.lowercased() }
    private var skipping: Bool { model.packSkippingBreak }

    private var methodText: String {
        if store.data.packStartDate != nil {
            return "Your pack day counts from the day you said you were on, and moves on by itself into each new pack: \(activeDays) active days" + (hasBreak ? ", then a \(packLength - activeDays)-day break." : ", no break.") + " Logged bleeds don't move it, but if one comes well before your break the app asks you to check. A few days into a new pack, it asks whether you started it on time. If it's off, set it again."
        }
        return "You haven't set your pack day yet, so this is a guess: it treats the first day of your last logged bleed as day \(model.packBleedStartDay) of a \(packLength)-day pack. Set your pack day to make it exact."
    }

    var body: some View {
        if model.packDayIsEstimated {
            CalloutBar(text: "This pack day is a guess from your last bleed. Set today\u{2019}s \(unit).",
                       systemImage: "questionmark.circle.fill", accent: .yellow) {
                withMotion(.reveal) { editing = true }
            }
        }
        header
        if model.pillToday != nil {
            RowCard { PillTodayRow() }
        }
        if skipping { skipNote }
        packCard
        RowCard {
            ExpandRow(title: "Not right? Set your pack day",
                      summary: model.packNextShort ?? "Pack type and today\u{2019}s \(unit)",
                      systemImage: "slider.horizontal.3", accent: .indigo, isExpanded: $editing) {
                PackSetupControl()
                    .foregroundStyle(Palette(scheme: scheme).primary)
            }
        }
        MethodSafetyRows(method: method)
    }

    // MARK: Summary

    /// The status in one or two sentences. Why the bleed isn't a period is
    /// behind the ⓘ on the break-week legend line.
    private var statusLine: String {
        let newPack = packLength - day + 1
        if isBreak {
            return "A withdrawal bleed usually comes in these days. New \(method == .combinedPill ? "pack" : "cycle") in \(newPack) day\(newPack == 1 ? "" : "s")."
        }
        if !hasBreak {
            return "You skip the break, so no withdrawal bleed is due. Some spotting can happen, especially in the first months; that's common."
        }
        let toBreak = activeDays - day + 1
        if skipping {
            return "You\u{2019}re skipping this break: \(toBreak) active day\(toBreak == 1 ? "" : "s") left, then straight into your next \(method == .combinedPill ? "pack" : unitName)."
        }
        return "Your \(breakName) start\(breakName.hasSuffix("s") ? "" : "s") in \(toBreak) day\(toBreak == 1 ? "" : "s") (\(breakDateText)). Expect a withdrawal bleed then."
    }

    private var info: Explanation {
        let topic = Topic.pillPack.explanation
        return Explanation(id: topic.id, title: topic.title, meaning: topic.meaning, forYou: topic.forYou, howWeGotIt: methodText)
    }

    private var header: some View {
        SummaryHeader(eyebrow: method.rawValue,
                      value: method == .combinedPill ? "Pill \(day) of \(packLength)" : "Day \(day) of \(packLength)",
                      status: SummaryStatus(text: isBreak ? model.packBreakName : model.packActiveName,
                                            accent: isBreak ? .pink : .indigo),
                      line: statusLine, accent: .pink, info: info)
    }

    private var skipNote: some View {
        Card(accent: .indigo) {
            Label("Skipping this break", systemImage: "forward.end.fill")
                .font(.bodyEmphasis)
                .foregroundStyle(Accent.indigo.ink(scheme))
            Text("Your next \(method == .combinedPill ? "pack" : unitName) starts \(model.nextPackStart.map { PackPosition.shortDate($0) } ?? "soon"), right after your last active day, so no withdrawal bleed is due this time. Some spotting is common.")
                .font(.bodyText).fixedSize(horizontal: false, vertical: true)
            Button("Undo") { model.undoSkipBreak() }
                .font(.bodyEmphasis)
                .foregroundStyle(Accent.indigo.ink(scheme))
                .frame(minHeight: 44)
        }
    }

    // MARK: Pack

    /// At rest the readout says what's next, not what the header already
    /// says (F19): "Next · Break week Nov 1–7", or in the break "Break week
    /// now · New pack Nov 8".
    private var restReadout: CycleReadout {
        let style: Date.FormatStyle = .dateTime.month(.abbreviated).day()
        let newPack = model.nextPackStart.map { "New pack \($0.formatted(style))" } ?? "New pack soon"
        if isBreak {
            return CycleReadout(title: "\(model.packBreakName) now", value: newPack, accent: .pink)
        }
        guard hasBreak, !skipping, let start = position.breakStart,
              let end = Calendar.current.date(byAdding: .day, value: packLength - activeDays - 1, to: start) else {
            return CycleReadout(title: "Next", value: newPack, accent: .indigo)
        }
        let cal = Calendar.current
        let endText = cal.isDate(start, equalTo: end, toGranularity: .month)
            ? end.formatted(.dateTime.day()) : end.formatted(style)
        return CycleReadout(title: "Next", value: "\(model.packBreakName) \(start.formatted(style))\u{2013}\(endText)", accent: .pink)
    }

    /// A picked pill's readout, with whether it was taken (H-A1).
    private func pickedReadout(_ d: Int, marks: AppModel.PillMarks) -> CycleReadout {
        var r = CycleCopy.packReadout(day: d, activeDays: activeDays, packLength: packLength, isToday: d == day,
                                      activeName: model.packActiveName, breakName: model.packBreakName)
        if marks.taken.contains(d) {
            r.title += " \u{00B7} taken"
        } else if marks.notLogged.contains(d) {
            r.title += " \u{00B7} not logged"
        }
        return r
    }

    private var packCard: some View {
        let marks = model.pillMarks
        let r = selected.map { pickedReadout($0, marks: marks) } ?? restReadout
        return Card {
            // Title and value only: what each part of the pack does to
            // energy, sleep and mood is on "How your pack affects you".
            ChartReadout(title: r.title, value: r.value, accent: r.accent,
                         onClear: selected == nil ? nil : { selected = nil })
            PillGrid(day: day, activeDays: activeDays, packLength: packLength, skipped: skipping,
                     marks: marks, selected: $selected)
            // It's a pack, not a chart (F21).
            ScrubHint(text: method == .combinedPill ? "Tap a pill to see its day." : "Tap a day to see it.")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(BodyLogStyle.packFill(isBreak: false, scheme)).frame(width: 10, height: 10)
                    Text("\(model.packActiveName) \u{00B7} days 1\u{2013}\(activeDays)").font(.secondary).fontWeight(.semibold)
                    InfoButton(topic: .pillPack).padding(.vertical, -10)
                }
                if !marks.notLogged.isEmpty {
                    HStack(spacing: 6) {
                        Circle().strokeBorder(BodyLogStyle.packFill(isBreak: false, scheme), lineWidth: 2).frame(width: 10, height: 10)
                        Text("Not marked taken").font(.secondary).fontWeight(.semibold)
                    }
                    .frame(minHeight: 28)
                }
                if hasBreak {
                    HStack(spacing: 6) {
                        Circle().strokeBorder(BodyLogStyle.packFill(isBreak: true, scheme), style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 12, height: 12)
                        Text(isBreak ? "\(model.packBreakName) \u{00B7} now"
                             : skipping ? "\(model.packBreakName) \u{00B7} skipped this time"
                             : "\(model.packBreakName) \u{00B7} from \(breakDateText)").font(.secondary).fontWeight(.semibold)
                        InfoButton(topic: .withdrawalBleed).padding(.vertical, -10)
                    }
                } else {
                    Text("Continuous use \u{00B7} no break week").font(.secondary).fontWeight(.semibold)
                }
            }
            .secondaryText()
        }
    }
}

/// The 28-day pack as a 7-column grid. Drag across it to see each day.
/// Pills she marked taken are filled in; active days since she started
/// marking them with nothing logged stay outlined (H-A1).
private struct PillGrid: View {
    let day: Int
    let activeDays: Int
    let packLength: Int
    /// She's skipping this pack's break: those days are shown greyed out.
    var skipped = false
    var marks = AppModel.PillMarks()
    @Binding var selected: Int?
    @Environment(\.colorScheme) private var scheme

    private let columns = 7
    private let rowHeight: CGFloat = 32
    private let spacing: CGFloat = 10
    private var rows: Int { (packLength + columns - 1) / columns }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { col in
                            pill(row * columns + col + 1)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, alignment: .top)
            .contentShape(Rectangle())
            .overlay(ScrubSurface { location in
                // Written only when the day changes, so a drag within one
                // pill doesn't redraw the screen (Weber D).
                let d = index(at: location, width: geo.size.width)
                if d != selected { selected = d }
            })
        }
        .scrubFeedback(selected)
        .frame(height: CGFloat(rows) * rowHeight + CGFloat(rows - 1) * spacing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((activeDays < packLength
                            ? "Pack: day \(day) of \(packLength). Days 1 to \(activeDays) active, then the break\(skipped ? ", skipped this time" : "")."
                            : "Pack: day \(day) of \(packLength), all active.")
                            + (marks.taken.isEmpty ? "" : " \(marks.taken.count) marked taken\(marks.notLogged.isEmpty ? "" : ", \(marks.notLogged.count) not")."))
        .accessibilityAdjustableAction { direction in
            let current = selected ?? day
            switch direction {
            case .increment: selected = min(current + 1, packLength)
            case .decrement: selected = max(current - 1, 1)
            @unknown default: break
            }
        }
    }

    private func index(at p: CGPoint, width: CGFloat) -> Int {
        let colW = (width + spacing) / CGFloat(columns)
        let col = min(max(Int(p.x / max(colW, 1)), 0), columns - 1)
        let row = min(max(Int(p.y / (rowHeight + spacing)), 0), rows - 1)
        return min(row * columns + col + 1, packLength)
    }

    @ViewBuilder
    private func pill(_ d: Int) -> some View {
        let isBreak = activeDays < packLength && d > activeDays
        let fill = BodyLogStyle.packFill(isBreak: isBreak, scheme)
        let shape = Capsule()
        ZStack {
            if d > packLength {
                Color.clear
            } else if d == day && marks.taken.contains(d) {
                shape.fill(fill).overlay(shape.strokeBorder(Color.white, lineWidth: 3).padding(-3))
                    .overlay(Image(systemName: "checkmark").font(.scaled(size: 14, weight: .heavy)).foregroundStyle(Color(hex: 0x0B0B14)))
            } else if d == day {
                shape.fill(Color.white).overlay(shape.strokeBorder(fill, lineWidth: 3).padding(-3))
            } else if marks.notLogged.contains(d) {
                shape.fill(fill.opacity(0.14)).overlay(shape.strokeBorder(fill, lineWidth: 2))
            } else if isBreak && skipped {
                shape.strokeBorder(Palette(scheme: scheme).tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            } else if isBreak {
                // Dashed, so break days differ from active ones by more than color.
                shape.fill(fill.opacity(0.12)).overlay(shape.strokeBorder(fill, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
            } else if d < day {
                shape.fill(fill)
            } else {
                // Full-strength border: 4.5:1 on the light card, 7:1 on the dark one.
                shape.fill(fill.opacity(0.14)).overlay(shape.strokeBorder(fill, lineWidth: 2))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .overlay {
            if selected == d { shape.strokeBorder(Palette(scheme: scheme).primary, lineWidth: 2).padding(-4) }
        }
    }
}

// MARK: - Implant, shot, and the hormonal IUD / mini pill past their usual length

/// Methods that stop ovulation without a pack (implant, shot): no phases,
/// no countdown. Also the hormonal IUD and mini pill once a gap runs past
/// her usual length: a long gap between bleeds is common on them, so it's
/// a bleeding history, not "overdue".
private struct SuppressedSection: View {
    let method: BirthControl
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    private var name: String { method.inSentence }
    /// Hormonal IUD or mini pill: ovulation may still happen.
    private var mayOvulate: Bool { method.ovulation != .stopped }

    private var heroText: String {
        switch method {
        case .hormonalIUD:
            return "A long gap between bleeds is common on the hormonal IUD. Periods often get lighter, come less often, or stop. So the app doesn\u{2019}t count down to a period or call a cycle late. Pregnancy is very rare with an IUD, but a positive test or pregnancy symptoms need a doctor soon."
        case .miniPill:
            return "A long gap between bleeds is common on the mini pill. Bleeding can come at unexpected times or stop for a while. So the app doesn\u{2019}t count down to a period or call a cycle late. Late with a pill or think you could be pregnant? Take a pregnancy test."
        default:
            return "Your \(name) stops your body from releasing an egg, so you don\u{2019}t have cycle phases, and the app doesn\u{2019}t count down to a period."
        }
    }

    /// The last few bleeds she logged (or Apple Health has), newest first.
    private var recentStarts: [Date] { Array(model.allPeriodStarts.suffix(4).reversed()) }

    var body: some View {
        Card {
            Text(BodyLogStyle.todayLine).font(.secondary).fontWeight(.bold).foregroundStyle(Accent.indigo.ink(scheme))
            Text("On the \(name)").font(.detailTitle).accessibilityAddTraits(.isHeader)
            Text(heroText)
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            if let days = model.daysSinceLastPeriodStart {
                Label(days == 0 ? "Bleeding started today" : "Last bleeding started \(days) day\(days == 1 ? "" : "s") ago", systemImage: "drop.fill")
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.pink.ink(scheme))
            }
        }
        if !recentStarts.isEmpty { historyCard }
        Card(accent: .mint) {
            SectionLabel(text: "Bleeding on your method", accent: .mint)
            Text("Bleeding may be light, come at random times, or stop completely. All of that is expected on the \(name) and isn't a sign that something is wrong.")
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Log any bleeding or spotting and we'll keep a history you can show your doctor.")
                .font(.bodyText)
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
        Card {
            SectionLabel(text: "Still tracked")
            Text(mayOvulate
                 ? "Your temperature, HRV and resting heart rate, compared with your own usual. You may still ovulate, and the app can\u{2019}t tell which part of your cycle you\u{2019}re in, so the sick check doesn\u{2019}t assume a phase. If it flags something, it says your cycle could be part of it."
                 : "Your temperature, HRV and resting heart rate, compared with your own usual. With no monthly hormone swings, changes in them are more likely to be about sleep, stress or getting sick.")
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        MethodSafetyRows(method: method)
    }

    private var historyCard: some View {
        Card {
            SectionLabel(text: "Your recent bleeds")
            ForEach(Array(recentStarts.enumerated()), id: \.offset) { i, start in
                HStack {
                    Text(start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                        .font(.bodyEmphasis)
                    Spacer()
                    if i + 1 < recentStarts.count,
                       let gap = Calendar.current.dateComponents([.day], from: recentStarts[i + 1], to: start).day {
                        Text("\(gap) days after the one before").font(.secondary).secondaryText()
                    }
                }
                .frame(minHeight: 32)
                .accessibilityElement(children: .combine)
            }
            Text("Started on these days. A history like this is what a doctor will ask about.")
                .font(.secondary).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pack, position not known

/// Pill, ring or patch when she hasn't said where she is in her pack and
/// there's no bleed to guess from: ask, instead of showing a made-up pack.
private struct PackUnknownSection: View {
    let method: BirthControl
    @Environment(\.colorScheme) private var scheme

    private var unit: String { method == .combinedPill ? "pill" : "day" }

    var body: some View {
        Card {
            Text(BodyLogStyle.todayLine).font(.secondary).fontWeight(.bold).foregroundStyle(Accent.indigo.ink(scheme))
            Text("Set where you are in your pack").font(.detailTitle).accessibilityAddTraits(.isHeader)
            Text("The app doesn\u{2019}t know which \(unit) you\u{2019}re on yet, so it can\u{2019}t show your active days and break week. Pick today\u{2019}s \(unit) from your pack.")
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        Card {
            PackSetupControl()
        }
        Card(accent: .indigo) {
            SectionLabel(text: "On your \(method.inSentence)", accent: .indigo)
            Text("It stops your body from releasing an egg, so there are no ovulation or luteal phases and no period countdown. The bleed in your break week is a withdrawal bleed.")
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "Learn how it affects your body", systemImage: "book.fill", accent: .indigo) {
                BirthControlLearnView()
            }
        }
        MethodSafetyRows(method: method)
    }
}

// MARK: - Overdue

/// A natural cycle running more than a few days past her usual length: no
/// phase, no countdown, no luteal adjustments. Just where she is and what
/// to do, in calm colors (a longer cycle now and then is common).
private struct OverdueSection: View {
    let day: Int
    let typicalLength: Int
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    private var doctorText: String {
        let base = "You could be pregnant, your cycle runs more than a couple of weeks longer than usual, or long cycles keep happening. Campus health is a good place to start. \(CycleCare.redS)"
        guard store.birthControl == .copperIUD else { return base }
        return "On the copper IUD pregnancy is rare, but a longer cycle is still worth a home pregnancy test. If it\u{2019}s positive, see a doctor soon: a pregnancy with an IUD in place needs checking quickly. Also check in if long cycles keep happening."
    }

    var body: some View {
        Card {
            Text(BodyLogStyle.todayLine).font(.secondary).fontWeight(.bold).foregroundStyle(Accent.indigo.ink(scheme))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Day \(day)").font(.display)
                InfoButton(explanation: Explanation(id: "overdue", title: "A longer cycle",
                                                   meaning: "Cycles vary. One that runs past your usual length now and then is common: stress, illness, travel, changes in sleep or exercise can all delay ovulation, and the period with it.",
                                                   forYou: "Log your period when it starts and the app picks up from there. If you could be pregnant: \(CycleCare.pregnancyTestTiming)"))
            }
            Text("Longer than \(model.usualLengthPhrase(typicalLength))")
                .font(.cardTitle)
                .accessibilityAddTraits(.isHeader)
            Text("No period logged yet this cycle. The app doesn\u{2019}t guess a phase or a date while a cycle runs longer than usual, so nothing here counts down.")
                .font(.bodyText)
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink { CycleLogView() } label: {
                Label("Log a period", systemImage: "drop.fill")
                    .font(.cardTitle)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(scheme == .dark ? Color(hex: 0x0E1136) : .white)
                    .background(scheme == .dark ? Accent.indigo.fill(.dark) : Accent.indigo.ink(.light), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        CycleCalendarCard()
        Card(accent: .indigo) {
            SectionLabel(text: "If your cycles often vary this much", accent: .indigo)
            Text("Switch to irregular tracking. The app then counts days since your last period and leaves out predictions and countdowns.")
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                store.data.cycleSetup = .irregular
            } label: {
                Text("Switch to irregular")
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Accent.indigo.fill(scheme).opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        CycleCareNotes()
        Card {
            Text("Check in with a doctor if").font(.bodyEmphasis)
            Text(doctorText)
                .font(.bodyText)
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Irregular, PCOS

private struct IrregularSection: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedLabel: String? = nil

    /// One finished cycle (start date and length), or the current one so far.
    private struct CycleBar: Identifiable {
        let id: Int
        let start: Date?
        let days: Int
        var isCurrent = false
        /// The x-axis category: the start date ("Aug 3"), or "Now".
        var label: String {
            if isCurrent { return "Now" }
            return start.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "Cycle \(id)"
        }
    }

    /// Finished cycles: the gaps between known period starts, each labelled
    /// with the day it started. Never a prediction.
    private var bars: [CycleBar] {
        let starts = model.allPeriodStarts
        let lengths = model.loggedCycleLengths
        let shown = Array(lengths.enumerated()).suffix(6)
        return shown.enumerated().map { i, pair in
            CycleBar(id: i + 1, start: pair.offset < starts.count ? starts[pair.offset] : nil, days: pair.element)
        }
    }

    /// The cycle she's in now, so far (an outlined bar, not a prediction).
    private var currentBar: CycleBar? {
        guard !bars.isEmpty, let days = model.daysSinceLastPeriodStart, days > 0 else { return nil }
        // Days since it started, the same number as the hero above and the
        // Body tile (round 3, N11: "53 d so far" under "52 days since").
        return CycleBar(id: bars.count + 1, start: model.allPeriodStarts.last, days: days, isCurrent: true)
    }

    private var chartBars: [CycleBar] { bars + (currentBar.map { [$0] } ?? []) }

    var body: some View {
        Card {
            Text("Your cycle, your way").font(.detailTitle).accessibilityAddTraits(.isHeader)
            if let days = model.daysSinceLastPeriodStart {
                if days == 0 {
                    Text("Your period started today").font(.section).foregroundStyle(Accent.pink.ink(scheme))
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(days)").font(.display).foregroundStyle(Accent.pink.ink(scheme))
                        Text("day\(days == 1 ? "" : "s") since your last period started").font(.bodyEmphasis).secondaryText()
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text("Log the first day of your next period and we'll start counting from there.")
                    .font(.bodyText)
                    .secondaryText()
            }
            Text("No countdown here. Your cycles vary a lot, so a predicted date would be wrong more often than right.")
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        historyCard
        Card(accent: .indigo) {
            SectionLabel(text: "What we can tell you", accent: .indigo)
            Text(model.ovulationStopped
                 ? "Your birth control stops your body from releasing an egg, so the app keeps a history of the bleeding you log. No predictions."
                 : "The app doesn't predict ovulation or periods for irregular cycles. It keeps a history of the periods you log, which is the most useful thing to bring to a doctor.")
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            if model.cycleIsNatural {
                Text(CycleCare.redS)
                    .font(.secondary)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        CycleCareNotes()
    }

    @ViewBuilder
    private var historyCard: some View {
        Card {
            SectionLabel(text: bars.isEmpty ? "Your cycle lengths" : "Your last \(bars.count) cycles")
            if bars.isEmpty {
                Text("Log the first day of each period and we'll keep a history of your cycle lengths. That's useful to share with a doctor.")
                    .font(.bodyText)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ChartReadout(title: readoutTitle, value: readoutValue, detail: readoutDetail, accent: .pink,
                             onClear: selectedLabel == nil ? nil : { selectedLabel = nil })
                cycleChart
                ScrubHint(each: "cycle")
            }
        }
    }

    private var shownBar: CycleBar? {
        guard let s = selectedLabel else { return nil }
        return chartBars.first { $0.label == s }
    }

    private var readoutTitle: String {
        guard let b = shownBar else { return "Range" }
        if b.isCurrent { return "This cycle so far" }
        return "Started \(b.label) \u{00B7} cycle \(b.id) of \(bars.count)"
    }
    private var readoutValue: String {
        if let b = shownBar { return b.isCurrent ? "\(b.days) days so far" : "\(b.days) days" }
        let lengths = bars.map(\.days)
        return "\(lengths.min() ?? 0)\u{2013}\(lengths.max() ?? 0) days"
    }
    private var hasPCOS: Bool { store.data.conditions.contains("PCOS") }

    private var readoutDetail: String {
        if let b = shownBar {
            if b.isCurrent {
                return "Still going, so this isn\u{2019}t a length yet and not a prediction. It becomes a full bar when you log your next period."
            }
            if b.days > 45 {
                return hasPCOS ? "A long cycle, over 45 days. Common with PCOS. Worth noting for your doctor."
                               : "A long cycle, over 45 days. Worth noting for your doctor."
            }
            if b.days > 35 { return "Longer than the typical 21\u{2013}35 days. Worth mentioning to a clinician if it keeps happening." }
            if b.days < 21 { return "A short cycle. Worth mentioning to a clinician if it keeps happening." }
            return "Within the typical 21\u{2013}35 day range."
        }
        let lengths = bars.map(\.days)
        let spread = (lengths.max() ?? 0) - (lengths.min() ?? 0)
        if lengths.count < 2 { return "Typical cycles are 21\u{2013}35 days. Log more periods to see how yours vary." }
        // FIGO 2018: up to 9 days at 18–25, 7 days at 26–41 (Okafor L).
        let limit = CycleEstimator.spreadLimit(ageYears: store.data.ageYears)
        if spread <= limit { return "Your cycles were within \(spread) day\(spread == 1 ? "" : "s") of each other. Typical cycles are 21\u{2013}35 days." }
        return "Your cycles varied by \(spread) days; more than \(limit) counts as irregular. Typical cycles are 21\u{2013}35 days. Worth mentioning to a clinician, with this history."
    }

    private var cycleChart: some View {
        // A category per cycle (its start date), so every bar gets a real
        // band to fill; a numeric x gave each bar a sliver and drew nothing.
        let fill = BodyLogStyle.phaseFill(.period, scheme)
        let ink = Accent.pink.ink(scheme)
        let top = max(chartBars.map(\.days).max() ?? 35, 35)
        return Chart(chartBars) { bar in
            if bar.isCurrent {
                // Faint fill with a dashed outline: the current cycle isn't
                // finished, so it never looks like a measured length.
                BarMark(x: .value("Cycle", bar.label), y: .value("Days", bar.days), width: .ratio(0.6))
                    .foregroundStyle(fill.opacity(0.14))
                    .cornerRadius(6)
                    .annotation(position: .overlay) {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(fill, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(shownBar == nil || shownBar?.isCurrent == true ? 1 : 0.35)
                    }
                    .annotation(position: .top, spacing: 2) {
                        // The same size as the finished bars' labels (Weber C9).
                        Text("\(bar.days) d so far").font(.secondary).fontWeight(.bold).foregroundStyle(ink)
                    }
            } else {
                BarMark(x: .value("Cycle", bar.label), y: .value("Days", bar.days), width: .ratio(0.6))
                    .foregroundStyle(fill)
                    .opacity(shownBar == nil || shownBar?.id == bar.id ? 1 : 0.35)
                    .cornerRadius(6)
                    .annotation(position: .top, spacing: 2) {
                        Text("\(bar.days) d").font(.secondary).fontWeight(.bold).foregroundStyle(ink)
                    }
            }
        }
        .chartXScale(domain: chartBars.map(\.label))
        .chartYScale(domain: 0...(Double(top) * 1.2))
        .chartScrub($selectedLabel, snapped: selectedLabel == nil ? nil : shownBar?.label, steps: chartBars.map(\.label))
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.chartLabel(size: 11, weight: .semibold))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel().font(.chartLabel(size: 11))
            }
        }
        .frame(height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cycleChartSummary)
        .accessibilityChartDescriptor(CategoryChartDescriptor(
            title: "Cycle lengths", seriesName: "Cycle starting", yTitle: "Days",
            points: chartBars.map { ($0.label, Double($0.days)) }, yLabel: { "\(Int($0.rounded())) days" }))
    }

    private var cycleChartSummary: String {
        var parts = bars.map { "started \($0.label), \($0.days) days" }
        if let c = currentBar { parts.append("this cycle so far, \(c.days) days") }
        return "Cycle lengths: " + parts.joined(separator: "; ")
    }
}
