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
        Screen(title: "Stress", accent: .coral) {
            SampleDataBanner()
            heroCard(day)
            chartCard(day)
            momentsCard(day)
            feelCard
            tipsCard
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
        case .none: return .coral
        }
    }

    private func vsUsual(_ day: StressDay) -> String {
        guard let label = day.label else {
            if !model.restingHRBaselineKnown {
                return "The app needs a few days of your resting heart rate before it can tell what's raised for you. Wear your Watch, including to bed."
            }
            return "Not enough still hours with heart rate data yet today. Wear your Watch and check back later."
        }
        switch label {
        case .low: return "Your heart stayed close to its resting pace while you were still. A calm day so far."
        case .usual: return "Normal day-to-day ups and downs."
        case .raised: return "Your heart has been working harder than usual while you were sitting still. " + otherCauses
        case .high: return "Your heart has been working much harder than usual while you were still. " + otherCauses + " A break, slow breathing or some fresh air can help."
        }
    }

    /// Body signals aren't only stress (round 4, Laurent F2). Her cycle is
    /// named only when it can move her heart rate.
    private var otherCauses: String {
        "That can be stress, but caffeine, some medicines, heat, a big meal or getting sick can do it too"
            + (model.heartFollowsCycle ? ", and so can the second half of your cycle." : ".")
    }

    // MARK: Hero

    private func heroCard(_ day: StressDay) -> some View {
        let p = Palette(scheme: scheme)
        let accent = labelAccent(day.label)
        return Card(accent: .coral) {
            HStack(spacing: 0) {
                SectionLabel(text: "Body signals, not how you feel", accent: .coral)
                InfoButton(topic: .stress).padding(.vertical, -14)
                Spacer()
            }
            // What she said comes first; the body's band second (round 4,
            // Laurent F2). A band only, no 0–100 number (Liu 9).
            if let felt = model.stressLoggedToday {
                Text("You said you felt \(feelName(felt).lowercased()) (\(felt) of 5).")
                    .font(.scaled(size: 17, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            AdaptiveStack(spacing: 10, alignment: .firstTextBaseline) {
                Text(day.label?.rawValue ?? "No data yet")
                    .font(.scaledNumber(day.label == nil ? 28 : 44))
                    .foregroundStyle(accent.ink(scheme))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if day.label != nil {
                    Text("from heart rate at rest").font(.scaled(size: 15, weight: .semibold)).foregroundStyle(p.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Text(vsUsual(day))
                .font(.scaled(size: 15))
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HowWeGotThisLink(title: "Your stress level", method: method(day))
        }
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

    @ViewBuilder
    private func readout(_ day: StressDay) -> some View {
        if let hour = nearestHour(day) {
            if hour.asleep {
                ChartReadout(title: Self.hourText(hour.hour), value: "Asleep",
                             detail: "Sleep hours aren't counted, so they don't make your day look calmer than it was.",
                             accent: .indigo)
            } else if hour.active {
                ChartReadout(title: Self.hourText(hour.hour), value: "Active",
                             detail: "You were moving. Moving raises heart rate too, so this hour isn't counted as stress.",
                             accent: .indigo)
            } else if hour.coolingDown {
                ChartReadout(title: Self.hourText(hour.hour), value: "Settling",
                             detail: "The hour after you were moving. Your heart rate is still coming down, so it isn't counted as stress.",
                             accent: .indigo)
            } else if let level = hour.level {
                let b = Self.band(level)
                ChartReadout(title: Self.hourText(hour.hour), value: b.name,
                             detail: Self.meaning(level), accent: b.accent)
            } else {
                ChartReadout(title: Self.hourText(hour.hour), value: "No reading",
                             detail: "Your Watch had no heart rate for this hour, often because it was off or charging.",
                             accent: .indigo)
            }
        } else if let peak = day.peak, let level = peak.level {
            ChartReadout(title: "Highest today \u{00B7} \(Self.hourText(peak.hour))", value: Self.band(level).name,
                         detail: "Touch the chart to see any hour.", accent: Self.band(level).accent)
        } else {
            ChartReadout(title: "Today", value: "No readings yet",
                         detail: "Hours fill in as your Watch measures your heart rate.", accent: .coral)
        }
    }

    private func chartCard(_ day: StressDay) -> some View {
        let p = Palette(scheme: scheme)
        return Card {
            Text("Hour by hour").font(.scaled(size: 17, weight: .bold))
            readout(day)
            StressHoursChart(hours: day.hours, selected: nearestHour(day)?.hour, selection: $selectedHour)
                .frame(height: 170)
            ScrubHint()
            // Wraps (one per line at the largest sizes) instead of breaking
            // the words into letters.
            FlowLayout(spacing: 12, lineSpacing: 6) {
                swatch(StressLevelColor.fill(0, scheme), "Low")
                swatch(StressLevelColor.fill(1, scheme), StressDay.Label.usual.rawValue)
                swatch(StressLevelColor.fill(2, scheme), "Raised \u{25CF}")
                swatch(StressLevelColor.fill(3, scheme), "High \u{25B2}")
                swatch(p.primary.opacity(0.18), "Active")
            }
            Text("Each hour is colored by band, darkest for High. High hours also get a \u{25B2} and Raised hours a \u{25CF}. Grey hours were active (including workouts without many steps, like swimming or lifting). Exercise raises heart rate too, so those hours, and hours asleep, aren't counted as stress.")
                .font(.scaled(size: 13))
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func swatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(text).font(.scaled(size: 12, weight: .semibold)).secondaryText()
                .keepsOnOneLine(minimumScale: 0.8)
        }
    }

    // MARK: Peak and calm

    private func momentsCard(_ day: StressDay) -> some View {
        AdaptiveStack(spacing: 10) {
            StressStat(title: "Peak",
                       value: day.peak.map { Self.hourText($0.hour) } ?? "\u{2014}",
                       note: day.peak?.level.map { Self.band($0).name } ?? "no readings yet",
                       accent: .coral,
                       explanation: Explanation(id: "stressPeak", title: "Peak hour",
                                                meaning: "The still hour today when your heart rate was furthest above your resting rate.",
                                                forYou: "Think about what was happening then: a deadline, a class, a hard conversation. Knowing your triggers is the first step to planning around them."))
            StressStat(title: "Calmest stretch",
                       value: day.calmestStretch?.label ?? "\u{2014}",
                       note: day.calmestStretch == nil ? "needs two still hours" : "your body's quietest time",
                       accent: .mint,
                       explanation: Explanation(id: "stressCalm", title: "Calmest stretch",
                                                meaning: "The two hours in a row, between 8am and 10pm, when your body was calmest.",
                                                forYou: "A good time for focused work or anything that needs a clear head."))
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
            Text("How stressed do you feel?").font(.scaled(size: 17, weight: .bold))
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
            .font(.scaled(size: 12, weight: .semibold))
            .foregroundStyle(p.secondary)
            .accessibilityHidden(true)
            StressCrisisRow(level: model.stressLoggedToday)
            if justLogged {
                Text("Saved. Logging how you feel lets you compare it with what your body shows.")
                    .font(.scaled(size: 13))
                    .foregroundStyle(Accent.mint.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            SectionLabel(text: "Last 7 days")
            HStack(spacing: 6) {
                ForEach(model.moodWeek, id: \.day) { entry in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(moodColor(entry.stress))
                            .overlay(Circle().strokeBorder(p.cardBorder))
                            .frame(width: 26, height: 26)
                            .overlay(Text(entry.stress.map { "\($0)" } ?? "").font(.scaled(size: 11, weight: .bold)))
                        Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.scaled(size: 11, weight: .semibold))
                            .foregroundStyle(p.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.day.formatted(.dateTime.weekday(.wide))): \(entry.stress.map { feelName($0) } ?? "not logged")")
                }
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

    private func feelButton(_ n: Int, selected: Bool) -> some View {
        let p = Palette(scheme: scheme)
        return Button {
            store.data.moodLog.append(AppData.MoodEntry(date: .now, stress: n))
            justLogged = true
        } label: {
            Text("\(n)")
                .font(.scaledNumber(22))
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(selected ? Color(hex: 0x1A0E00) : p.primary)
                .background(selected ? Accent.coral.fill(scheme) : p.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Accent.coral.fill(scheme) : p.cardBorder))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(n), \(feelName(n))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Tips

    private var tipsCard: some View {
        Card {
            Text("What helps").font(.scaled(size: 17, weight: .bold))
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
                   detail: "A short night makes the next day feel more stressful. Aim for bed by \(Clock.format(store.data.bedtime)).")
        }
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
            if h.active { return StressBar(hour: h.hour, level: 100, active: true) }
            guard let level = h.level else { return nil }
            return StressBar(hour: h.hour, level: max(level, 3), active: false)
        }
    }

    private var domain: ClosedRange<Int> {
        let hs = hours.map(\.hour)
        return min(hs.min() ?? 7, 7)...max((hs.max() ?? 22) + 1, 22)
    }

    private func color(_ bar: StressBar) -> Color {
        let base: Color = bar.active
            ? Palette(scheme: scheme).primary.opacity(0.18)
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
            PointMark(x: .value("Hour", selected), y: .value("Level", bar.level))
                .foregroundStyle(Palette(scheme: scheme).primary)
                .symbolSize(40)
        }
    }

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Hour", bar.hour), y: .value("Level", bar.level), width: .fixed(12))
                    .foregroundStyle(color(bar))
                    .cornerRadius(3)
                    .annotation(position: .top, spacing: 2) {
                        // Not color alone: High hours get a ▲ and Raised a ●.
                        // No numbers: a band, not a precise score (round 4, Liu 9).
                        if !bar.active, StressView.bandIndex(bar.level) == 3 {
                            Text("\u{25B2}").font(.scaled(size: 8, weight: .heavy))
                                .foregroundStyle(StressLevelColor.fill(3, scheme))
                        } else if !bar.active, StressView.bandIndex(bar.level) == 2 {
                            // Raised gets its own mark too: green Low and amber
                            // Raised are a colour-blind pair (round 3).
                            Text("\u{25CF}").font(.scaled(size: 6, weight: .heavy))
                                .foregroundStyle(StressLevelColor.fill(2, scheme))
                        }
                    }
            }
            .accessibilityHidden(true)   // VoiceOver reads the chart's summary instead (round 3, A9)
            selectionMarks.accessibilityHidden(true)
        }
        .chartScrub($selection)
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

private struct StressStat: View {
    var title: String
    var value: String
    var note: String
    var accent: Accent
    var explanation: Explanation
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text(title).font(.scaled(size: 13, weight: .bold)).foregroundStyle(p.secondary)
                Spacer(minLength: 0)
                InfoButton(explanation: explanation).padding(.vertical, -14).padding(.horizontal, -8)
            }
            Text(value).font(.scaledNumber(20)).minimumScaleFactor(0.6).lineLimit(1)
            Text(note).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(accent.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(p.cardBorder))
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
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 34, height: 34)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(size: 15, weight: .bold))
                Text(detail)
                    .font(.scaled(size: 13))
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
