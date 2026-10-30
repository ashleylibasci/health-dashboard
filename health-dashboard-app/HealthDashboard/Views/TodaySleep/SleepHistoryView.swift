import SwiftUI
import Charts
import HealthCore

/// Every night of the last week or month, or each week of the last six
/// months (D-G2), against her sleep need, plus averages.
struct SleepHistoryView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @AppStorage("sleepHistory.range") private var range: TrendRange = .week
    /// The nights before the loaded ones, read when she picks 6M.
    @State private var older: [NightRecord] = []
    @State private var selectedDay: Date? = nil

    private var nights: [NightRecord] { model.trendNights(range, older: older) }
    /// On 6M: each week's average time asleep.
    private var weeks: [WeeklyAverage] {
        WeeklyAverage.by(nights, date: \.wakeDay, value: { Double($0.asleepMinutes) })
    }
    private var need: Int { model.sleepNeed.minutes }

    /// During the first 14 nights the history mixes example nights with hers.
    private var mixesExamples: Bool { model.usingSampleData && model.realNightCount > 0 }
    private func isExample(_ night: NightRecord) -> Bool { model.usingSampleData && !model.isRealNight(night) }
    /// Only marked while the history mixes both (all-example history is flagged by the banner).
    private var exampleDays: Set<Date> {
        guard mixesExamples else { return [] }
        return Set(nights.filter(isExample).map { Calendar.current.startOfDay(for: $0.wakeDay) })
    }
    private var metDays: Set<Date> {
        Set(nights.filter { model.metNeed($0) }.map { Calendar.current.startOfDay(for: $0.wakeDay) })
    }

    var body: some View {
        Screen(title: "Sleep history", accent: .purple) {
            SampleDataBanner()
            TrendRangePicker(range: $range, accent: .purple)
                .padding(.top, 4)
                .onChange(of: range) { selectedDay = nil }
                .task(id: range) {
                    if range == .sixMonths { older = await model.olderTrendNights() }
                }
            if nights.isEmpty {
                Card {
                    Text("No nights yet").font(.cardTitle)
                    Text("Wear your Watch to bed and your nights will show up here.")
                        .font(.bodyText)
                        .secondaryText()
                }
            } else {
                chartCard
                averagesCard
            }
        }
    }

    // MARK: Chart

    private var selectedNight: NightRecord? {
        guard let selectedDay, !range.isWeekly else { return nil }
        return nights.min { abs($0.wakeDay.timeIntervalSince(selectedDay)) < abs($1.wakeDay.timeIntervalSince(selectedDay)) }
    }

    private var selectedWeek: WeeklyAverage? {
        guard let selectedDay, range.isWeekly else { return nil }
        return weeks.min { abs($0.week.timeIntervalSince(selectedDay)) < abs($1.week.timeIntervalSince(selectedDay)) }
    }

    /// "4 of 6 nights reached your need", for a week on 6M.
    private func weekDetail(_ week: WeeklyAverage) -> String {
        let cal = Calendar.current
        let inWeek = nights.filter { cal.isDate($0.wakeDay, equalTo: week.week, toGranularity: .weekOfYear) }
        return "\(inWeek.filter { model.metNeed($0) }.count) of \(inWeek.count) nights reached your need"
    }

    private func dateText(_ day: Date) -> String {
        // The night before the wake day.
        let night = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        return "Night of " + night.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func vsNeed(_ asleep: Int) -> String {
        let gap = asleep - need
        if abs(gap) <= 10 { return "about your need" }
        return gap < 0 ? "\(Clock.duration(-gap)) under your need" : "\(Clock.duration(gap)) over your need"
    }

    private func nightDetail(_ night: NightRecord) -> String {
        "Bed \(Clock.format(night.bedtime)) \u{00B7} up \(Clock.format(night.wake)) \u{00B7} \(vsNeed(night.asleepMinutes))"
    }

    private var summaryDetail: String {
        "Your need is \(Clock.duration(need)), the dashed line. \(metCount) of \(nights.count) nights reached it."
    }

    @ViewBuilder
    private var readout: some View {
        let slots = [summaryDetail] + (range.isWeekly ? weeks.map(weekDetail) : nights.map(nightDetail))
        if let week = selectedWeek {
            ChartReadout(title: "Week of \(week.week.formatted(.dateTime.month(.abbreviated).day())) \u{00B7} average asleep",
                         value: Clock.duration(Int(week.value.rounded())),
                         detail: weekDetail(week),
                         accent: SleepNeedEstimator.metNeed(asleep: Int(week.value.rounded()), need: need) ? .purple : .coral,
                         onClear: { selectedDay = nil }, detailSlots: slots)
        } else if let night = selectedNight {
            let source = model.usingSampleData ? (isExample(night) ? "Example night \u{00B7} " : "Your night \u{00B7} ") : ""
            ChartReadout(title: source + dateText(night.wakeDay) + " \u{00B7} asleep",
                         value: Clock.duration(night.asleepMinutes),
                         detail: nightDetail(night),
                         accent: model.metNeed(night) ? .purple : .coral,
                         onClear: { selectedDay = nil }, detailSlots: slots)
        } else {
            let avg = averageAsleep
            ChartReadout(title: "\(range.title) \u{00B7} average",
                         value: Clock.duration(avg),
                         detail: summaryDetail,
                         accent: .purple, detailSlots: slots)
        }
    }

    private var metCount: Int { nights.filter { model.metNeed($0) }.count }

    private var chartCard: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("Time asleep").font(.cardTitle)
                Spacer()
                HStack(spacing: 0) {
                    Text("Need \(Clock.duration(need))").font(.secondary).fontWeight(.semibold).secondaryText()
                    InfoButton(topic: .sleepNeed).padding(.vertical, -12)
                }
            }
            readout
            HistoryBars(nights: nights, need: need, metDays: metDays, exampleDays: range.isWeekly ? [] : exampleDays,
                        selected: range.isWeekly ? selectedWeek?.week : selectedNight?.wakeDay,
                        selection: $selectedDay.snapping { raw in
                            range.isWeekly
                                ? weeks.min { abs($0.week.timeIntervalSince(raw)) < abs($1.week.timeIntervalSince(raw)) }?.week
                                : nights.min { abs($0.wakeDay.timeIntervalSince(raw)) < abs($1.wakeDay.timeIntervalSince(raw)) }?.wakeDay
                        },
                        barWidth: range == .week ? 22 : 6, range: range)
                .frame(height: 200)
                .motion(.dataSwap, value: range)
            ScrubHint(each: range.step)
            if mixesExamples && !range.isWeekly {
                Text("Faded bars are example nights. Solid bars are your own nights from Apple Health.")
                    .font(.secondary)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Averages

    private var averageAsleep: Int {
        Int((nights.map { Double($0.asleepMinutes) }.mean ?? 0).rounded())
    }

    private var averagesCard: some View {
        let bed = Clock.circularMean(nights.map(\.bedtime))
        let wake = Clock.circularMean(nights.map(\.wake))
        let steadiness = model.steadiness(of: nights)
        return Card {
            Text("Your averages").font(.cardTitle)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    AverageTile(title: "Asleep", value: Clock.duration(averageAsleep),
                                note: vsNeed(averageAsleep), explanation: Topic.sleepNeed.explanation)
                    AverageTile(title: "Regularity", value: steadiness?.word ?? "\u{2014}",
                                note: steadiness.map { "Moved \(Clock.duration($0.moved)) a night" } ?? "needs 5 nights",
                                explanation: Topic.regularity.explanation)
                }
                GridRow {
                    AverageTile(title: "Bedtime", value: bed.map { Clock.format($0) } ?? "\u{2014}",
                                note: "you planned \(Clock.format(store.data.bedtime))",
                                explanation: Explanation(id: "avgBedtime", title: "Average bedtime",
                                                         meaning: "When you got into bed, averaged over these nights.",
                                                         forYou: "The closer this sits to the same time every night, the easier falling asleep gets."))
                    AverageTile(title: "Wake", value: wake.map { Clock.format($0) } ?? "\u{2014}",
                                note: "average wake-up",
                                explanation: Explanation(id: "avgWake", title: "Average wake time",
                                                         meaning: "When you woke up, averaged over these nights.",
                                                         forYou: "A steady wake time, even on weekends, sets your body clock more than anything else."))
                }
            }
        }
    }
}

// MARK: - Pieces

/// Time asleep per night (or, on 6M, each week's average) as bars against
/// the dashed need line (the Sleep tab's last 7 nights and this screen).
struct HistoryBars: View {
    let nights: [NightRecord]
    let need: Int
    /// Start-of-day wake days that met her need (`AppModel.metNeed`, the one threshold).
    let metDays: Set<Date>
    /// Start-of-day wake days that are example nights, drawn faded.
    let exampleDays: Set<Date>
    let selected: Date?
    @Binding var selection: Date?
    let barWidth: CGFloat
    /// The span the x axis covers, ending today: exactly 7 bars' worth of
    /// labels on a week, never an extra empty day (design flaw 5).
    var range: TrendRange = .week
    @Environment(\.colorScheme) private var scheme

    private var domain: ClosedRange<Date> { range.domain() }

    private var dayStarts: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: domain.lowerBound) }
    }

    private var weeks: [WeeklyAverage] {
        WeeklyAverage.by(nights, date: \.wakeDay, value: { Double($0.asleepMinutes) })
    }

    /// A week's bar: purple when its average met her need (the one
    /// threshold, `SleepNeedEstimator.metNeed`), coral when it didn't.
    private func color(_ week: WeeklyAverage) -> Color {
        let base = SleepNeedEstimator.metNeed(asleep: Int(week.value.rounded()), need: need)
            ? Accent.purple.fill(scheme) : Accent.coral.fill(scheme)
        guard let selected else { return base }
        return Calendar.current.isDate(week.week, inSameDayAs: selected) ? base : base.opacity(0.35)
    }

    private func day(_ night: NightRecord) -> Date { Calendar.current.startOfDay(for: night.wakeDay) }

    private var summary: String {
        if range.isWeekly {
            let short = weeks.filter { !SleepNeedEstimator.metNeed(asleep: Int($0.value.rounded()), need: need) }.count
            return "Average time asleep for each of \(weeks.count) weeks. \(short) averaged under your need of \(Clock.duration(need))."
        }
        let short = nights.filter { !metDays.contains(day($0)) }.count
        var text = "Time asleep for \(nights.count) nights. \(short) were under your need of \(Clock.duration(need))."
        let examples = nights.filter { exampleDays.contains(day($0)) }.count
        if examples > 0 {
            text += " \(examples) of the nights are examples, \(nights.count - examples) are yours."
        }
        return text
    }

    private func color(_ night: NightRecord) -> Color {
        var base = metDays.contains(day(night)) ? Accent.purple.fill(scheme) : Accent.coral.fill(scheme)
        if exampleDays.contains(day(night)) { base = base.opacity(0.45) }
        guard let selected else { return base }
        return Calendar.current.isDate(night.wakeDay, inSameDayAs: selected) ? base : base.opacity(0.35)
    }

    @ChartContentBuilder
    private var needLine: some ChartContent {
        RuleMark(y: .value("Hours", Double(need) / 60))
            .foregroundStyle(Palette(scheme: scheme).secondary)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    }

    @ChartContentBuilder
    private var selectionRule: some ChartContent {
        if let selected {
            RuleMark(x: .value("Night", selected, unit: range.unit))
                .foregroundStyle(Palette(scheme: scheme).primary.opacity(0.25))
        }
    }

    var body: some View {
        Chart {
            selectionRule
            if range.isWeekly {
                ForEach(weeks, id: \.week) { week in
                    BarMark(x: .value("Week", week.week, unit: .weekOfYear),
                            y: .value("Hours", week.value / 60),
                            width: .fixed(barWidth))
                        .foregroundStyle(color(week))
                        .cornerRadius(3)
                }
            } else {
                ForEach(nights, id: \.wakeDay) { night in
                    BarMark(x: .value("Night", night.wakeDay, unit: .day),
                            y: .value("Hours", Double(night.asleepMinutes) / 60),
                            width: .fixed(barWidth))
                        .foregroundStyle(color(night))
                        .cornerRadius(4)
                }
            }
            needLine
        }
        .chartScrub($selection, snapped: selected, steps: range.isWeekly ? weeks.map(\.week) : nights.map(\.wakeDay).sorted())
        .chartYScale(domain: 0.0...11.0)
        .chartXScale(domain: domain, range: .plotDimension(startPadding: 4, endPadding: 8))
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 4.0, 6.0, 8.0, 10.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let h = value.as(Double.self) { Text("\(Int(h))h") }
                }
            }
        }
        .chartXAxis {
            switch range {
            case .week:
                // One label per day in the domain, not one for its end too.
                AxisMarks(values: dayStarts) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            case .month:
                AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            case .sixMonths:
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
        .accessibilityLabel(summary)
        .accessibilityChartDescriptor(range.isWeekly
            ? DateChartDescriptor(
                title: "Average time asleep by week, last 6 months", seriesName: "Time asleep", yTitle: "Time asleep",
                points: weeks.map { ($0.week, $0.value) },
                yLabel: { Clock.duration(Int($0.rounded())) }, isContinuous: false)
            : DateChartDescriptor(
                title: "Time asleep, last \(nights.count) nights", seriesName: "Time asleep", yTitle: "Time asleep",
                points: nights.map { ($0.wakeDay, Double($0.asleepMinutes)) },
                yLabel: { Clock.duration(Int($0.rounded())) }, isContinuous: false))
    }
}

private struct AverageTile: View {
    var title: String
    var value: String
    var note: String
    var explanation: Explanation
    @Environment(\.colorScheme) private var scheme
    @State private var explaining: Explanation? = nil

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text(title).font(.secondary).fontWeight(.bold).foregroundStyle(p.secondary)
                Spacer(minLength: 0)
                InfoButton(explanation: explanation).padding(.vertical, -14).padding(.horizontal, -8)
                    .accessibilityHidden(true)
            }
            // "All over the place" shrinks to fit rather than wrapping.
            Text(value).font(.numberM).minimumScaleFactor(0.5).lineLimit(1)
            Text(note).font(.secondary).fontWeight(.semibold).foregroundStyle(Accent.purple.ink(scheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        // One stop per tile; the ⓘ is an "Explain" action (Ortiz F9).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value == "\u{2014}" ? "no value yet" : value), \(note)")
        .accessibilityAction(named: "Explain") { explaining = explanation }
        .sheet(item: $explaining) { ExplanationSheet(explanation: $0) }
    }
}
