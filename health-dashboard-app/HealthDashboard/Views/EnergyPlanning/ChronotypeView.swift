import SwiftUI
import Charts
import HealthCore

/// Your body clock: your type from tracked sleep first, the type scale,
/// then the weekend shift and what can move it one tap down. The method
/// lives behind the summary's ⓘ, not on the page.
struct ChronotypeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Screen(title: "Your body clock", accent: .orange) {
            SampleDataBanner()
            if let c = model.chronotype, !model.chronotypeIsLearning {
                summary(c)
                Card {
                    ChronotypeSpectrum(msfsc: c.midSleepFreeCorrected, category: c.category)
                }
                RowCard { rows(c) }
                Card(density: .compact) {
                    LearnMoreRow("Learn more about body clock types", article: .bodyClockTypes, accent: .orange)
                }
            } else {
                Card {
                    Text("Still learning your body clock").font(.cardTitle)
                    Text("We need school nights (with an alarm) and free nights (no alarm) tracked by your Watch. So far: \(model.workNights.count) school, \(model.freeNights.count) free. Check back after a weekend.")
                        .font(.bodyText).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Summary

    private func summary(_ c: Chronotype) -> some View {
        var pairs = [StatPair(label: "Body clock time", value: Clock.format(c.midSleepFreeCorrected))]
        if let wake = model.naturalWake {
            pairs.append(StatPair(label: "Wake, left alone", value: Clock.format(Int((Double(wake) / 15).rounded()) * 15)))
        }
        return SummaryHeader(eyebrow: "Your body clock type", value: c.category.rawValue,
                             line: Self.forAgeGroup(c.category), pairs: pairs, accent: .orange,
                             info: explanation(c))
    }

    /// The body clock ⓘ, with this method and what "body clock time" means
    /// under "How it's worked out".
    private func explanation(_ c: Chronotype) -> Explanation {
        let topic = Topic.bodyClock.explanation
        let corrected = c.midSleepFreeCorrected == c.midSleepFree
            ? ""
            : " Your raw free-day middle is \(Clock.format(c.midSleepFree)); without the catch-up sleep it's \(Clock.format(c.midSleepFreeCorrected))."
        let bodyClockTime = "Body clock time: the halfway point between falling asleep and waking up on days with no alarm, the simplest way to tell how early or late your body naturally runs. When you sleep longer on free days to catch up, that extra sleep pushes the raw middle later, so we take it out." + corrected
        return Explanation(id: "bodyClockType", title: topic.title, meaning: topic.meaning, forYou: topic.forYou,
                           howWeGotIt: method(c) + "\n\n" + bodyClockTime)
    }

    /// What each type means, in plain words.
    nonisolated static func plain(_ category: Chronotype.Category) -> String {
        switch category {
        case .veryEarly: return "Your body likes to sleep and wake much earlier than most people."
        case .moderateMorning: return "Your body leans toward earlier nights and earlier mornings."
        case .intermediate: return "Right in the middle: not an early bird, not a night owl."
        case .moderateEvening: return "Your body leans toward later nights and later mornings than most people. Very common at your age."
        case .definiteEvening: return "Your body clearly prefers late nights and late mornings. Common in your late teens and early twenties."
        case .veryLate: return "Your body runs much later than most people's, so early mornings feel especially hard."
        }
    }

    /// The type names compare her with adults of all ages, but body clocks
    /// run latest around 20 (Roenneberg 2004), so the same type means
    /// something different at her age (Liu 13). The app is for college
    /// students, so it compares with women in their late teens and early 20s.
    nonisolated static func forAgeGroup(_ category: Chronotype.Category) -> String {
        switch category {
        case .veryEarly: return "Much earlier than most adults, and earlier still compared with people your age (late teens and early 20s)."
        case .moderateMorning: return "Earlier than most adults, and earlier than most people your age (late teens and early 20s)."
        case .intermediate: return "About average for adults, a little earlier than typical for your age (late teens and early 20s)."
        case .moderateEvening: return "Later than most adults, typical for your age (late teens and early 20s)."
        case .definiteEvening: return "Later than most adults, and on the late side even for your age (late teens and early 20s)."
        case .veryLate: return "Later than most adults, and later than most people your age too."
        }
    }

    /// The method, short and plain, for the "how it's worked out" part.
    private func method(_ c: Chronotype) -> String {
        let n = model.workNights.count + model.freeNights.count
        let source = model.usingSampleData ? "Sample sleep is shown until your Watch has enough nights." : "From your last \(n) nights of sleep tracked by your Watch."
        return "\(source) We find the middle of your sleep on free nights (no alarm), when your body picks its own timing. If you sleep longer on free nights to catch up, we adjust for that, so catch-up sleep doesn't make you look later than you are. This is the standard method sleep researchers use (the Munich ChronoType Questionnaire). The type names compare you with adults of all ages; body clocks run latest around age 20, so we also say how you compare with people your age. Your type is partly genetic. It updates as new nights come in."
    }

    // MARK: Rows

    @ViewBuilder
    private func rows(_ c: Chronotype) -> some View {
        let over = c.socialJetlag >= 60
        MetricRow(title: "Weekend shift", note: "Later on free nights", value: Clock.duration(c.socialJetlag),
                  verdict: RowVerdict(text: over ? "Above goal" : "Under goal", accent: over ? .coral : .mint),
                  systemImage: "airplane", accent: .orange) { WeekendShiftView() }
        RowDivider()
        ExpandRow(title: "What can shift it",
                  summary: model.isEveningLeaning ? "Earlier, a little at a time" : "A little at a time",
                  systemImage: "arrow.left.arrow.right", accent: .orange) { shiftRows(c) }
        if !model.fallBackHasHappened && model.daysUntilFallBack <= 28 {
            RowDivider()
            MetricRow(title: "Clocks go back \(model.nextFallBack.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))",
                      note: model.isEveningLeaning ? "An 8am start feels like 9am for a few days" : "You'll wake an hour earlier by the clock",
                      systemImage: "clock.arrow.circlepath", accent: .indigo) { TimeChangeView() }
        }
    }

    @ViewBuilder
    private func shiftRows(_ c: Chronotype) -> some View {
        // After midnight this is the app day's daylight (yesterday's), not 0.
        let daylightText = model.daylightThisAppDay.map { "\($0) min today" } ?? "No reading yet today"
        let detail = shiftDetails(c)
        ChronoDetailRow(systemImage: "sun.max.fill", accent: .yellow, title: "Morning daylight",
                        detail: "The strongest signal your clock gets. \(daylightText). Time outside before noon, day after day, moves your peak earlier.")
        ChronoDetailRow(systemImage: "alarm.fill", accent: .orange, title: "A steady wake time", detail: detail.wake)
        ChronoDetailRow(systemImage: "calendar", accent: .purple, title: "A smaller weekend shift", detail: detail.shift)
    }

    /// A steady wake time and a smaller weekend shift, from her own nights.
    private func shiftDetails(_ c: Chronotype) -> (wake: String, shift: String) {
        let work = model.workNightWindow
        let free = model.freeNightWindow
        let wakeDetail: String
        let shiftDetail: String
        if let work, let free {
            let target = work.end + 60
            if free.end > target {
                wakeDetail = "Your wake time swings from \(Clock.format(work.end)) on school days to \(Clock.format(free.end)) on weekends. Getting up by \(Clock.format(target)) on Saturday and Sunday anchors the clock."
            } else {
                wakeDetail = "Your weekend wake-ups stay within an hour of \(Clock.format(work.end)). Keeping it that way anchors the clock."
            }
            let onset = roundUp15(work.start)
            let newGap = abs((onset + target) / 2 - (work.start + work.end) / 2)
            if c.socialJetlag > newGap + 10 {
                shiftDetail = "Asleep by \(Clock.format(onset)) and up by \(Clock.format(target)) on Fri and Sat cuts your weekend shift from \(Clock.duration(c.socialJetlag)) to about \(Clock.duration(newGap))."
            } else {
                shiftDetail = "Your weekend shift is already small. Keeping it under an hour protects Monday mornings."
            }
        } else {
            wakeDetail = "Getting up within an hour of your school-day time on weekends anchors the clock."
            shiftDetail = "Keeping weekend sleep within an hour of school nights protects Monday mornings."
        }
        return (wakeDetail, shiftDetail)
    }

    private func roundUp15(_ m: Minutes) -> Minutes { Int((Double(m) / 15).rounded(.up)) * 15 }
}

// MARK: - Weekend shift

/// How much later she sleeps on free nights than on school nights, with the
/// two sleep windows to drag along. Pushed from Your body clock.
private struct WeekendShiftView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    /// The selected time, snapped to 5 minutes.
    @State private var selection: Int? = nil

    var body: some View {
        Screen(title: "Weekend shift", accent: .orange) {
            if let c = model.chronotype {
                let sjl = c.socialJetlag
                let over = sjl >= 60
                SummaryHeader(eyebrow: "Weekend shift", value: Clock.duration(sjl), unit: "later",
                              status: SummaryStatus(text: over ? "Above goal" : "Under goal", accent: over ? .coral : .mint),
                              line: "How much later you sleep on free nights than on school nights. The goal is under 1 hour.",
                              accent: .orange, info: Topic.socialJetlag.explanation)
                if let work = model.workNightWindow, let free = model.freeNightWindow {
                    Card {
                        readout(work: work, free: free, c: c)
                        SleepWindowsChart(work: work, free: free, selected: selection,
                                          selection: $selection.snapping { Int((Double($0) / 5).rounded()) * 5 })
                            .frame(height: 110)
                            .accessibilityLabel("School nights asleep \(work.label.replacingOccurrences(of: "\u{2013}", with: " to ")), free nights asleep \(free.label.replacingOccurrences(of: "\u{2013}", with: " to ")). A \(Clock.duration(sjl)) gap in the middle of your sleep.")
                        ScrubHint(each: "hour of the night")
                        windowRow(accent: .indigo, name: "School nights", range: work.label,
                                  middle: "middle \(Clock.format(c.midSleepWork))")
                        windowRow(accent: .orange, name: "Free nights", range: free.label,
                                  middle: "middle \(Clock.format(c.midSleepFree))" + (c.midSleepFreeCorrected == c.midSleepFree ? "" : " (raw)"))
                    }
                }
                Card(accent: .orange) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "airplane")
                            .font(.bodyEmphasis)
                            .foregroundStyle(Accent.orange.ink(scheme))
                            .accessibilityHidden(true)
                        Text(why(sjl)).font(.bodyText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func readout(work: TimeRange, free: TimeRange, c: Chronotype) -> ChartReadout {
        let summaryNote = "School nights \(Clock.format(c.midSleepWork)), free nights \(Clock.format(c.midSleepFree))." + (c.midSleepFreeCorrected == c.midSleepFree ? "" : " Your body clock time, \(Clock.format(c.midSleepFreeCorrected)), takes out the catch-up sleep.")
        func state(_ r: TimeRange, at t: Int) -> String {
            if r.contains(t) { return "asleep until \(Clock.format(r.end))" }
            if t < r.start { return "awake, asleep at \(Clock.format(r.start))" }
            return "up since \(Clock.format(r.end))"
        }
        func note(at t: Int) -> String { "School nights: \(state(work, at: t)). Free nights: \(state(free, at: t))." }
        // The longest notes it can show: the summary, and the scrub note at
        // the windows' edges (the longest times print the most digits).
        let slots = [summaryNote] + [work.start, work.end, free.start, free.end, work.start - 30, free.end + 30].map(note(at:))
        guard let t = selection else {
            return ChartReadout(title: "Middle of your sleep \u{00B7} later on free nights",
                                value: Clock.duration(c.socialJetlag), detail: summaryNote, accent: .orange,
                                detailSlots: slots)
        }
        let value: String
        switch (work.contains(t), free.contains(t)) {
        case (true, true): value = "Asleep either way"
        case (false, true): value = "Asleep only on free nights"
        case (true, false): value = "Asleep only on school nights"
        case (false, false): value = "Awake either way"
        }
        return ChartReadout(title: Clock.format(t), value: value, detail: note(at: t), accent: .orange,
                            onClear: { selection = nil }, detailSlots: slots)
    }

    /// The name on the left, the range on the right on one line, and the
    /// middle of the night under it.
    private func windowRow(accent: Accent, name: String, range: String, middle: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Circle().fill(accent.fill(scheme)).frame(width: 10, height: 10).padding(.top, 5)
                .accessibilityHidden(true)
            Text(name).font(.bodyText).secondaryText()
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: 0) {
                Text(range).font(.bodyEmphasis).lineLimit(1).minimumScaleFactor(0.8)
                Text(middle).font(.secondary).secondaryText().lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func why(_ sjl: Int) -> String {
        let text = Clock.duration(sjl)
        if sjl >= 60 {
            return "Every weekend your body drifts \(text) later, then the Monday alarm pulls it back. It's like crossing \(timeZones(sjl)) and back each week, which is why Mondays feel rough."
        }
        return "Your weekends run only \(text) later than school nights, so Monday mornings stay close to your body's own timing."
    }

    private func timeZones(_ minutes: Int) -> String {
        let halves = Int((Double(minutes) / 30).rounded())
        let whole = halves / 2
        let half = halves % 2 == 1
        let names = [1: "one", 2: "two", 3: "three", 4: "four"]
        let word = names[whole] ?? "\(whole)"
        if whole == 1 && !half { return "one time zone" }
        return half ? "\(word) and a half time zones" : "\(word) time zones"
    }
}

// MARK: - Subviews

/// The very-early to very-late spectrum, 2am to 8am, with a marker. Drag
/// along it to see what each type means.
private struct ChronotypeSpectrum: View {
    var msfsc: Minutes
    var category: Chronotype.Category
    /// Where the finger is, snapped to 15 minutes of mid-sleep (1/24 of
    /// the scale), so a drag only redraws when the readout would change.
    @State private var dragFraction: CGFloat? = nil
    @Environment(\.colorScheme) private var scheme

    private var colors: [Color] {
        [Accent.yellow.fill(scheme),
         scheme == .dark ? Color(hex: 0xFFC56E) : Color(hex: 0xE8A33A),
         Accent.orange.fill(scheme),
         Accent.coral.fill(scheme),
         Accent.purple.fill(scheme),
         Accent.indigo.fill(scheme)]
    }

    private var index: Int { Chronotype.Category.allCases.firstIndex(of: category) ?? 2 }

    /// 0...1 across 2am–8am.
    private var fraction: CGFloat {
        let m = msfsc > 720 ? msfsc - 1440 : msfsc
        let f = (Double(m) - 120) / 360
        return CGFloat(min(max(f, 0.02), 0.98))
    }

    /// Every note the readout can show, so it keeps one height (Weber A1).
    private var slots: [String] {
        Chronotype.Category.allCases.flatMap { [ChronotypeView.plain($0), ChronotypeView.plain($0) + " That's you."] }
            + [Self.restNote]
    }

    private static let restNote = "The middle of your sleep on free nights, after catch-up sleep is taken off. The scale runs from very early to very late."

    /// "4th of 6": her type's place on the scale, earliest first.
    private var position: String {
        let n = index + 1
        let suffix = n == 1 ? "st" : n == 2 ? "nd" : n == 3 ? "rd" : "th"
        return "\(n)\(suffix) of \(Chronotype.Category.allCases.count)"
    }

    private var readout: ChartReadout {
        guard let f = dragFraction else {
            // At rest: where she sits, not the type the summary already
            // names (F18).
            return ChartReadout(title: "You", value: "\(Clock.format(msfsc)) \u{00B7} \(position)",
                                detail: Self.restNote, accent: .orange, detailSlots: slots)
        }
        let mid = 120 + Int((Double(f) * 360).rounded())
        let cat = Chronotype.category(for: mid)
        let you = cat == category ? " That's you." : ""
        return ChartReadout(title: "Middle of sleep around \(Clock.format(Int((Double(mid) / 15).rounded()) * 15))",
                            value: cat.rawValue,
                            detail: ChronotypeView.plain(cat) + you, accent: .orange,
                            onClear: { dragFraction = nil }, detailSlots: slots)
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 6) {
            readout
            GeometryReader { geo in
                let x = geo.size.width * fraction
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 3) {
                        ForEach(0..<6) { i in
                            Capsule()
                                .fill(colors[i])
                                .opacity(i == index ? 1 : 0.45)
                                .frame(height: 12)
                        }
                    }
                    .offset(y: 24)
                    Text("You")
                        .font(.secondary).fontWeight(.bold)
                        .position(x: x, y: 7)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(colors[index], lineWidth: 4))
                        .position(x: x, y: 30)
                    if let f = dragFraction {
                        Rectangle()
                            .fill(p.primary.opacity(0.6))
                            .frame(width: 2, height: 30)
                            .position(x: geo.size.width * f, y: 30)
                    }
                    ForEach(1..<6) { i in
                        Text("\(i + 2)am")
                            .font(.small).fontWeight(.semibold)
                            .foregroundStyle(p.tertiary)
                            .position(x: geo.size.width * CGFloat(i) / 6, y: 56)
                    }
                }
                .contentShape(Rectangle())
                .overlay(ScrubSurface { location in
                    let w = max(geo.size.width, 1)
                    let snapped = (min(max(location.x / w, 0), 1) * 24).rounded() / 24
                    if snapped != dragFraction { dragFraction = snapped }
                })
            }
            .frame(height: 64)
            // A tick every 15 minutes of mid-sleep, as the readout rounds.
            .scrubFeedback(dragFraction.map { Int((Double($0) * 24).rounded()) })
            HStack {
                Text("Very early")
                Spacer()
                Text("Very late")
            }
            .font(.secondary).fontWeight(.semibold)
            .foregroundStyle(p.secondary)
            ScrubHint(each: "type")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body clock spectrum from very early to very late. Your body clock time (free-day sleep middle, minus catch-up sleep) is \(Clock.format(msfsc)), a \(category.rawValue.lowercased()).")
    }
}

/// School-night vs free-day sleep windows on one timeline.
private struct SleepWindowsChart: View {
    var work: TimeRange
    var free: TimeRange
    var selected: Int?
    @Binding var selection: Int?
    @Environment(\.colorScheme) private var scheme

    private var lo: Int { min(work.start, free.start) - 30 }
    private var hi: Int { max(work.end, free.end) + 30 }
    private var ticks: [Int] {
        let first = Int((Double(lo) / 120).rounded(.up)) * 120
        return Array(stride(from: first, through: hi, by: 120))
    }

    var body: some View {
        Chart {
            bars
            mids
            selectionMark
        }
        .chartXScale(domain: lo...hi)
        .chartYAxis(.hidden)
        .accessibilityChartDescriptor(ClockChartDescriptor(
            title: "Sleep on school and free nights", seriesName: "Asleep", yTitle: "Night",
            points: [(work.start, 0), (work.end, 0), (free.start, 1), (free.end, 1)],
            yLabel: { $0 < 0.5 ? "School nights" : "Free nights" }))
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(Clock.format(m)).font(.chartLabel(size: 11)).foregroundStyle(Palette(scheme: scheme).tertiary)
                    }
                }
            }
        }
        // A tick per quarter hour, not per 5-minute step.
        .chartScrub($selection, snapped: selected, feedbackKey: { $0 / 15 })
        .transaction(value: selected) { $0.animation = nil }
    }

    @ChartContentBuilder private var bars: some ChartContent {
        BarMark(xStart: .value("Asleep", work.start), xEnd: .value("Woke", work.end), y: .value("Night", "School nights"))
            .foregroundStyle(Accent.indigo.fill(scheme))
            .cornerRadius(6)
        BarMark(xStart: .value("Asleep", free.start), xEnd: .value("Woke", free.end), y: .value("Night", "Free nights"))
            .foregroundStyle(Accent.orange.fill(scheme))
            .cornerRadius(6)
    }

    @ChartContentBuilder private var mids: some ChartContent {
        RuleMark(x: .value("Mid", (work.start + work.end) / 2))
            .foregroundStyle(Accent.indigo.ink(scheme))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        RuleMark(x: .value("Mid", (free.start + free.end) / 2))
            .foregroundStyle(Accent.orange.ink(scheme))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
    }

    @ChartContentBuilder private var selectionMark: some ChartContent {
        if let selected {
            RuleMark(x: .value("Selected", selected))
                .foregroundStyle(Palette(scheme: scheme).primary)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
    }
}

private struct ChronoDetailRow: View {
    var systemImage: String
    var accent: Accent
    var title: String
    var detail: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.bodyEmphasis)
                .foregroundStyle(accent.ink(scheme))
                .frame(width: Sizes.icon, height: Sizes.icon)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.bodyEmphasis)
                Text(detail).font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
