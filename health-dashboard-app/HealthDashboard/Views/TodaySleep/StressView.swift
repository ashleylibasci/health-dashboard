import SwiftUI
import Charts
import HealthCore

/// Today's stress from heart rate and HRV while sitting still, how she says
/// she feels, and what helps.
struct StressView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedHour: Int? = nil
    @State private var justLogged = false

    var body: some View {
        let day = model.stressToday
        // Stress is orange on every screen (Tanaka F1); the header takes the
        // colour of today's band (F6).
        Screen(title: "Stress", accent: .orange) {
            SampleDataBanner()
            header(day)
            chartCard(day)
            feelCard
            RowCard {
                if let label = day.label, label == .raised || label == .high {
                    ExpandRow(title: "What else raises it", summary: "Caffeine, heat, a meal, getting sick\u{2026}",
                              systemImage: "questionmark.circle.fill", accent: .orange) {
                        Text(otherCauses + (label == .high ? " A break, slow breathing or some fresh air can help." : ""))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    RowDivider()
                }
                ExpandRow(title: "Last 7 days", summary: weekSummary, systemImage: "calendar", accent: .orange) {
                    weekDots
                }
                RowDivider()
                ExpandRow(title: "What helps", summary: "Breathing, a walk, short work blocks",
                          systemImage: "leaf.fill", accent: .mint) {
                    tips
                }
            }
        }
    }

    // MARK: Words

    nonisolated static func hourText(_ h: Int) -> String {
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12)\(h % 24 < 12 ? "am" : "pm")"
    }

    /// The one label set (Low, Moderate, Raised, High), from HealthCore.
    nonisolated static func band(_ level: Int) -> (name: String, accent: Accent) {
        let label = StressModel.label(for: level)
        switch label {
        case .low: return (label.rawValue, .mint)
        case .usual: return (label.rawValue, .blue)
        case .raised: return (label.rawValue, .orange)
        case .high: return (label.rawValue, .coral)
        }
    }

    /// 0 Low, 1 Moderate, 2 Raised, 3 High (for `StressLevelColor`).
    nonisolated static func bandIndex(_ level: Int) -> Int {
        switch StressModel.label(for: level) {
        case .low: return 0
        case .usual: return 1
        case .raised: return 2
        case .high: return 3
        }
    }

    nonisolated static func meaning(_ level: Int) -> String {
        switch StressModel.label(for: level) {
        case .low: return "Low: your heart was close to its resting pace while you were still."
        case .usual: return "Moderate: normal day-to-day ups and downs. Nothing to do."
        case .raised: return "Raised: your heart rate was up while you were sitting still. Stress, caffeine, heat or a meal can all do that."
        case .high: return "High: your heart was working hard while you weren't moving. Stress, caffeine, heat, a meal or getting sick can all do that."
        }
    }

    private func labelAccent(_ label: StressDay.Label?) -> Accent {
        switch label {
        case .some(.low): return .mint
        case .some(.usual): return .blue
        case .some(.raised): return .orange
        case .some(.high): return .coral
        case .none: return .orange
        }
    }

    /// One sentence against her usual; what else can raise it is a row.
    private func vsUsual(_ day: StressDay) -> String {
        guard let label = day.label else {
            if !model.restingHRBaselineKnown {
                return "The app needs a few days of your resting heart rate before it can tell what's raised for you."
            }
            return "Not enough still hours with heart rate data yet today. Check back later."
        }
        switch label {
        case .low: return "Your heart stayed close to its resting pace while you were still. A calm day so far."
        case .usual: return "Normal day-to-day ups and downs."
        case .raised: return "Your heart has been working harder than usual while you were sitting still."
        case .high: return "Your heart has been working much harder than usual while you were still."
        }
    }

    /// Body signals aren't only stress (round 4, Laurent F2). Her cycle is
    /// named only when it can move her heart rate.
    private var otherCauses: String {
        "That can be stress, but caffeine, some medicines, heat, a big meal or getting sick can do it too"
            + (model.heartFollowsCycle ? ", and so can the second half of your cycle." : ".")
    }

    // MARK: Header

    /// The ⓘ: what the band is, with how it's worked out.
    private func info(_ day: StressDay) -> Explanation {
        let topic = Topic.stress.explanation
        return Explanation(id: topic.id, title: topic.title, meaning: topic.meaning, forYou: topic.forYou, howWeGotIt: method(day))
    }

    /// What she said comes first; the body's band second (round 4, Laurent
    /// F2). A band only, no 0–100 number (Liu 9).
    private func header(_ day: StressDay) -> some View {
        var pairs: [StatPair] = []
        if let peak = day.peak, let level = peak.level {
            pairs.append(StatPair(label: "Peak", value: "\(Self.hourText(peak.hour)) \u{00B7} \(Self.band(level).name)"))
        }
        if let calm = day.calmestStretch {
            pairs.append(StatPair(label: "Calmest", value: calm.label))
        }
        return SummaryHeader(eyebrow: "Body signals, not how you feel", value: day.label?.rawValue ?? "No data yet",
                             status: model.stressLoggedToday.map { SummaryStatus(text: "You felt \($0) of 5", accent: .orange) },
                             line: vsUsual(day), pairs: pairs, accent: labelAccent(day.label), info: info(day))
    }

    private func method(_ day: StressDay) -> String {
        let heart = model.stressStillBaseline != nil
            ? "Each hour we compare your heart rate with your own heart rate in still, awake hours over the last 2 weeks: three times your usual spread above it is the top of the scale."
            : "Each hour we compare your heart rate with your resting heart rate: 25 beats above it is the top of the scale. Once there are enough still hours from the last 2 weeks, we compare with your own still-hour heart rate instead."
        let cycle = model.heartFollowsCycle
            ? " In the second half of a natural cycle your heart runs a little faster on its own, so 2 beats and 5% of HRV are allowed for then."
            : ""
        return heart + " Your HRV is compared with your usual daytime HRV; half your usual is the top. Only hours when you were awake and still count. Hours you were asleep are left out, and so are hours you were moving (\(model.hidesActivityNumbers ? "from your steps and active energy" : "over about \(Int(StressModel.activeSteps)) steps, or \(Int(model.stressActiveKcal.rounded())) active calories or more, about 1 per kg of your weight"), which also catches swimming, cycling and lifting) and the hour right after, while your heart rate settles." + cycle + " Without a few days of your heart data there's no label yet. Today's band comes from the average of the counted hours (\(day.countedHours) so far), split into four: Low, Moderate, Raised and High. It's shown as a band rather than a number because a Watch reading isn't that precise. It measures your body, not your mood: caffeine, medicines, heat and meals move it too."
    }

    // MARK: Hourly chart

    private func nearestHour(_ day: StressDay) -> StressDay.Hour? {
        guard let selectedHour else { return nil }
        return day.hours.min { abs($0.hour - selectedHour) < abs($1.hour - selectedHour) }
    }

    /// Every note the readout can show, so it keeps one height while she
    /// drags.
    private static let readoutSlots = [
        "Sleep hours aren't counted, so they don't make your day look calmer than it was.",
        "You were moving. Moving raises heart rate too, so this hour isn't counted as stress.",
        "The hour after you were moving. Your heart rate is still coming down, so it isn't counted as stress.",
        "Your Watch had no heart rate for this hour, often because it was off or charging.",
    ] + (0...100).map(meaning).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

    @ViewBuilder
    private func readout(_ day: StressDay) -> some View {
        let slots = Self.readoutSlots
        if let hour = nearestHour(day) {
            if hour.asleep {
                ChartReadout(title: Self.hourText(hour.hour), value: "Asleep", detail: slots[0],
                             accent: .purple, onClear: { selectedHour = nil }, detailSlots: slots)
            } else if hour.active {
                ChartReadout(title: Self.hourText(hour.hour), value: "Active", detail: slots[1],
                             accent: .indigo, onClear: { selectedHour = nil }, detailSlots: slots)
            } else if hour.coolingDown {
                ChartReadout(title: Self.hourText(hour.hour), value: "Settling", detail: slots[2],
                             accent: .indigo, onClear: { selectedHour = nil }, detailSlots: slots)
            } else if let level = hour.level {
                let b = Self.band(level)
                ChartReadout(title: Self.hourText(hour.hour), value: b.name,
                             detail: Self.meaning(level), accent: b.accent, onClear: { selectedHour = nil }, detailSlots: slots)
            } else {
                ChartReadout(title: Self.hourText(hour.hour), value: "No reading", detail: slots[3],
                             accent: .indigo, onClear: { selectedHour = nil }, detailSlots: slots)
            }
        } else if let latest = day.hours.last(where: { $0.level != nil }), let level = latest.level {
            // At rest: the latest counted hour, not the peak the summary
            // already shows (F15).
            let b = Self.band(level)
            let isNow = latest.hour == (model.now / 60) % 24
            ChartReadout(title: "\(isNow ? "Now" : "Latest") \u{00B7} \(Self.hourText(latest.hour))", value: b.name,
                         detail: Self.meaning(level), accent: b.accent, detailSlots: slots)
        } else {
            ChartReadout(title: "Today", value: "No readings yet",
                         detail: "Hours fill in as your Watch measures your heart rate.", accent: .orange, detailSlots: slots)
        }
    }

    /// The legend and how to read the chart, behind the card's ⓘ.
    private static let chartExplanation = Explanation(
        id: "stressHours", title: "Hour by hour",
        meaning: "Each hour is colored by band, darkest for High. High hours also get a \u{25B2} and Raised hours a \u{25CF}. The short grey marks along the bottom are active hours (including workouts without many steps, like swimming or lifting). Exercise raises heart rate too, so those hours, and hours asleep, aren't counted as stress.",
        forYou: "Peak hour: the still hour today when your heart rate was furthest above your resting rate. Think about what was happening then: a deadline, a class, a hard conversation. Knowing your triggers is the first step to planning around them. Calmest stretch: the two hours in a row, between 8am and 10pm, when your body was calmest. A good time for focused work or anything that needs a clear head.")

    private func chartCard(_ day: StressDay) -> some View {
        let p = Palette(scheme: scheme)
        let hasReadings = day.hours.contains { $0.level != nil || $0.active }
        return Card {
            HStack(spacing: 0) {
                Text("Hour by hour").font(.cardTitle)
                Spacer(minLength: 0)
                InfoButton(explanation: Self.chartExplanation).padding(.vertical, -12)
            }
            if hasReadings {
                readout(day)
                StressHoursChart(hours: day.hours, selected: nearestHour(day)?.hour, selection: $selectedHour)
                    .frame(height: 170)
                legend
                ScrubHint(each: "hour")
            } else {
                // No empty grid: one line until the first hour comes in.
                Label("Fills in as your Watch measures your heart rate.", systemImage: "applewatch")
                    .font(.bodyText).foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One line when it fits, else two equal columns; a swatch before every
    /// label and no stray glyphs (the ▲ and ● are in the card's ⓘ, F16).
    private var legend: some View {
        let items: [(Color, String)] = [
            (StressLevelColor.fill(0, scheme), "Low"),
            (StressLevelColor.fill(1, scheme), StressDay.Label.usual.rawValue),
            (StressLevelColor.fill(2, scheme), "Raised"),
            (StressLevelColor.fill(3, scheme), "High"),
            (Palette(scheme: scheme).tertiary, "Active"),
        ]
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ForEach(items, id: \.1) { swatch($0.0, $0.1).fixedSize() }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                    GridRow {
                        swatch(items[i].0, items[i].1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if i + 1 < items.count {
                            swatch(items[i + 1].0, items[i + 1].1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
    }

    private func swatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(text).font(.secondary).fontWeight(.semibold).secondaryText()
                .keepsOnOneLine(minimumScale: 0.8)
        }
    }

    // MARK: How do you feel

    /// The Log tab's words for the same 1–5 scale, so the two never disagree.
    private let feelNames = (1...5).map { n -> String in
        let w = LogView.stressWord(n)
        return w.prefix(1).uppercased() + w.dropFirst()
    }
    private func feelName(_ n: Int) -> String { feelNames[min(max(n, 1), 5) - 1] }

    private var feelCard: some View {
        let p = Palette(scheme: scheme)
        let current = model.stressLoggedToday ?? 0
        return Card {
            Text("How stressed do you feel?").font(.cardTitle)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { n in
                    feelButton(n, selected: n == current)
                }
            }
            HStack {
                Text(feelNames[0])
                Spacer()
                Text(feelNames[4])
            }
            .font(.secondary).fontWeight(.semibold)
            .foregroundStyle(p.secondary)
            .accessibilityHidden(true)
            if justLogged {
                Text("Saved. Logging how you feel lets you compare it with what your body shows.")
                    .font(.secondary)
                    .foregroundStyle(Accent.mint.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var weekSummary: String {
        let logged = model.moodWeek.filter { $0.stress != nil }.count
        return logged == 0 ? "Nothing logged yet" : "\(logged) of 7 days logged"
    }

    private var weekDots: some View {
        let p = Palette(scheme: scheme)
        return HStack(spacing: 6) {
            ForEach(model.moodWeek, id: \.day) { entry in
                VStack(spacing: 4) {
                    Circle()
                        .fill(moodColor(entry.stress))
                        .overlay(Circle().strokeBorder(p.cardBorder))
                        .frame(width: 26, height: 26)
                        .overlay(Text(entry.stress.map { "\($0)" } ?? "").font(.small).fontWeight(.bold)
                            .foregroundStyle(p.primary))
                    Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.small).fontWeight(.semibold)
                        .foregroundStyle(p.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.day.formatted(.dateTime.weekday(.wide))): \(entry.stress.map { feelName($0) } ?? "not logged")")
            }
        }
    }

    private func moodColor(_ stress: Int?) -> Color {
        guard let stress else { return Palette(scheme: scheme).chip }
        switch stress {
        case 1, 2: return Accent.mint.fill(scheme).opacity(0.6)
        case 3: return Accent.yellow.fill(scheme).opacity(0.6)
        default: return Accent.coral.fill(scheme).opacity(0.7)
        }
    }

    /// Orange, the stress colour; the deep ink in light mode so the white
    /// number on it passes 4.5:1.
    private var selectedFill: Color { scheme == .dark ? Accent.orange.fill(.dark) : Accent.orange.ink(.light) }

    private func feelButton(_ n: Int, selected: Bool) -> some View {
        let p = Palette(scheme: scheme)
        return Button {
            store.data.moodLog.append(AppData.MoodEntry(date: .now, stress: n))
            justLogged = true
        } label: {
            Text("\(n)")
                .font(.numberM)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(selected ? (scheme == .dark ? Color(hex: 0x1A0E00) : .white) : p.primary)
                .background(selected ? selectedFill : p.chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                    .strokeBorder(selected ? selectedFill : p.cardBorder))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(n), \(feelName(n))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Tips

    @ViewBuilder
    private var tips: some View {
        HelpTipRow(systemImage: "wind", accent: .mint, title: "1 minute of slow breathing",
                   detail: "Breathe in for 4, out for 6. Long out-breaths slow your heart. The Mindfulness app on your Watch can guide you.")
        if model.hidesEffortTargets {
            HelpTipRow(systemImage: "sun.max.fill", accent: .blue, title: "A few minutes outside",
                       detail: "Daylight and a change of scene help stress hormones settle.")
        } else {
            HelpTipRow(systemImage: "figure.walk", accent: .blue, title: "A 10-minute walk outside",
                       detail: "Moving and daylight bring stress hormones down, and walking isn't counted as stress here.")
        }
        HelpTipRow(systemImage: "timer", accent: .indigo, title: "Work in 25-minute blocks",
                   detail: "Short, clear chunks with breaks feel less overwhelming than one long push before a deadline.")
        HelpTipRow(systemImage: "cup.and.saucer.fill", accent: .yellow, title: "Go easy on late caffeine",
                   detail: "Caffeine raises your heart rate and can make stress feel worse, and it lingers into the night.")
        HelpTipRow(systemImage: "moon.fill", accent: .purple, title: "Protect tonight's sleep",
                   detail: "A short night makes the next day feel more stressful. Aim for bed by \(Clock.format(model.tonightBedtime)).")
    }
}

// MARK: - Pieces

private struct StressBar: Identifiable {
    var id: Int { hour }
    let hour: Int
    let level: Int
    let active: Bool
}

private struct StressHoursChart: View {
    let hours: [StressDay.Hour]
    let selected: Int?
    @Binding var selection: Int?
    @Environment(\.colorScheme) private var scheme

    private var bars: [StressBar] {
        hours.compactMap { h in
            if h.active { return StressBar(hour: h.hour, level: 0, active: true) }
            guard let level = h.level else { return nil }
            return StressBar(hour: h.hour, level: max(level, 3), active: false)
        }
    }

    /// The height of an active hour's cap (the chart runs to 115).
    static let activeCap = 6

    private var domain: ClosedRange<Int> {
        let hs = hours.map(\.hour)
        return min(hs.min() ?? 7, 7)...max((hs.max() ?? 22) + 1, 22)
    }

    private func color(_ bar: StressBar) -> Color {
        let base: Color = bar.active
            ? Palette(scheme: scheme).tertiary
            : StressLevelColor.fill(StressView.bandIndex(bar.level), scheme)
        guard let selected else { return base }
        return selected == bar.hour ? base : base.opacity(0.4)
    }

    private var summary: String {
        let counted = hours.compactMap { h -> String? in
            guard let l = h.level else { return nil }
            return "\(StressView.hourText(h.hour)) \(StressView.band(l).name.lowercased())"
        }
        let active = hours.filter(\.active).map { StressView.hourText($0.hour) }
        var text = "Stress by hour today: " + counted.joined(separator: ", ") + "."
        if !active.isEmpty { text += " Active, not counted: " + active.joined(separator: ", ") + "." }
        return text
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let selected, let bar = bars.first(where: { $0.hour == selected }) {
            RuleMark(x: .value("Hour", selected))
                .foregroundStyle(Palette(scheme: scheme).primary.opacity(0.3))
            PointMark(x: .value("Hour", selected), y: .value("Level", bar.active ? Self.activeCap : bar.level))
                .foregroundStyle(Palette(scheme: scheme).primary)
                .symbolSize(40)
        }
    }

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                // An active hour is a short cap on the baseline, not a full
                // grey bar that out-shouts the stress (Tanaka F11).
                BarMark(x: .value("Hour", bar.hour), yStart: .value("Level", 0),
                        yEnd: .value("Level", bar.active ? Self.activeCap : bar.level), width: .fixed(12))
                    .foregroundStyle(color(bar))
                    .cornerRadius(3)
                    .annotation(position: .top, spacing: 2) {
                        // Not color alone: High hours get a ▲ and Raised a ●.
                        // No numbers: a band, not a precise score (round 4, Liu 9).
                        if !bar.active, StressView.bandIndex(bar.level) == 3 {
                            Text("\u{25B2}").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(StressLevelColor.fill(3, scheme))
                        } else if !bar.active, StressView.bandIndex(bar.level) == 2 {
                            // Raised gets its own mark too: green Low and amber
                            // Raised are a colour-blind pair (round 3).
                            Text("\u{25CF}").font(.system(size: 6, weight: .bold))
                                .foregroundStyle(StressLevelColor.fill(2, scheme))
                        }
                    }
            }
            selectionMarks
        }
        // VoiceOver reads the chart's summary (chartScrub makes it one
        // element); hiding the marks risked dropping the ▲/● labels (Weber A8).
        .chartScrub($selection, snapped: selected, steps: bars.map(\.hour).sorted())
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...115)  // room above 100 for the labels
        .chartXAxis {
            AxisMarks(values: [8, 12, 16, 20]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let h = value.as(Int.self) { Text(StressView.hourText(h)) }
                }
            }
        }
        .chartYAxis {
            // Gridlines at the band edges, no numbers.
            AxisMarks(position: .leading, values: [20, 40, 60]) { _ in AxisGridLine() }
        }
        .accessibilityLabel(summary)
        .accessibilityChartDescriptor(ClockChartDescriptor(
            title: "Stress by hour today", seriesName: "Stress band", yTitle: "Stress band, Low to High",
            points: hours.compactMap { h in h.level.map { (h.hour * 60, Double($0)) } },
            yLabel: { StressView.band(Int($0.rounded())).name }))
    }
}

/// An icon, a bold line and a one-line why.
private struct HelpTipRow: View {
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
                Text(detail)
                    .font(.secondary)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
