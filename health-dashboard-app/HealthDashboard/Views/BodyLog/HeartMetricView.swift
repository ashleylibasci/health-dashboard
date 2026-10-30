import SwiftUI
import Charts
import HealthCore

// HRV and resting heart rate: the detail screen behind the Body tab's
// vitals and Recovery, the rows that open it, its trend card and the chart.
// Moved out of BodyView.swift so the detail screens own them.

/// HRV, resting heart rate or sleep over the last week, month or six months
/// (D-G2), with her break weeks shaded behind (D-G3). Drag across it to read
/// any night (or week) against your usual.
struct BodyTrendCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var metric: Metric
    /// A month by default: the 30 nights her usual comes from.
    @AppStorage("bodyTrend.range") private var range: TrendRange = .month
    /// The nights before the loaded ones, read when she picks 6M.
    @State private var older: [NightRecord] = []
    @State private var selected: Date? = nil

    init(metric: Metric = .hrv) {
        _metric = State(wrappedValue: metric)
    }

    enum Metric: String, CaseIterable, Hashable {
        case hrv = "HRV", restingHR = "Resting HR", sleep = "Sleep"

        var spoken: String {
            switch self {
            case .hrv: "HRV"
            case .restingHR: "Resting heart rate"
            case .sleep: "Sleep"
            }
        }
    }

    /// Each night, or on 6M each week's average.
    private var points: [NightTrendPoint] {
        let nightly = model.bodyTrend(range, older: older).compactMap { t -> NightTrendPoint? in
            switch metric {
            case .hrv: return t.hrv.map { NightTrendPoint(date: t.date, value: $0) }
            case .restingHR: return t.restingHR.map { NightTrendPoint(date: t.date, value: $0) }
            case .sleep: return NightTrendPoint(date: t.date, value: Double(t.asleep) / 60)
            }
        }
        guard range.isWeekly else { return nightly }
        return WeeklyAverage.by(nightly, date: \.date, value: \.value)
            .map { NightTrendPoint(date: $0.week, value: $0.value, nights: $0.nights) }
    }

    private var usual: Double {
        switch metric {
        case .hrv: return model.baselineHRV
        case .restingHR: return model.baselineRestingHR
        case .sleep: return Double(model.sleepNeed.minutes) / 60
        }
    }

    /// One hue per measure (Tanaka F1): HRV indigo, resting HR pink, sleep purple.
    private var accent: Accent {
        switch metric {
        case .hrv: .indigo
        case .restingHR: .pink
        case .sleep: .purple
        }
    }

    /// HRV and resting heart rate get the wording for her method.
    private var explanation: Explanation {
        switch metric {
        case .hrv: model.hrvExplanation
        case .restingHR: model.restingHRExplanation
        case .sleep: Topic.sleepNeed.explanation
        }
    }

    private func shown(in points: [NightTrendPoint]) -> NightTrendPoint? {
        guard let s = selected else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) }
    }

    private func format(_ v: Double) -> String {
        switch metric {
        case .hrv: return "\(Int(v.rounded())) ms"
        case .restingHR: return "\(Int(v.rounded())) bpm"
        case .sleep: return Clock.duration(Int((v * 60).rounded()))
        }
    }

    /// Coral only when the night was worse in a way worth acting on
    /// (Valtonen F4): HRV well below, resting HR up, sleep well short.
    private func isWorse(_ v: Double) -> Bool {
        let d = v - usual
        switch metric {
        case .hrv:
            let pct = usual > 0 ? d / usual * 100 : 0
            return HeartBands.hrv(deltaPct: pct, spreadPct: model.hrvSpreadPct) == .wellBelow
        case .restingHR:
            let level = HeartBands.restingHR(delta: d)
            return level == .above || level == .wellBelow
        case .sleep:
            return Int((d * 60).rounded()) <= -45
        }
    }

    private func meaning(_ v: Double) -> String {
        let d = v - usual
        switch metric {
        case .hrv:
            // Bands against her own spread; the cycle named only when hers
            // can move it (round 4, Brandt F8/F9, Laurent F10).
            let pct = usual > 0 ? d / usual * 100 : 0
            switch HeartBands.hrv(deltaPct: pct, spreadPct: model.hrvSpreadPct) {
            case .wellBelow: return "Well below your usual \(Int(usual.rounded())) ms: your body was under strain (short sleep, stress, drinks or getting sick\(model.heartCycleCause))."
            case .below: return "A little below your usual \(Int(usual.rounded())) ms. Normal day-to-day wobble."
            case .usual: return "Right around your usual \(Int(usual.rounded())) ms."
            case .above: return "Above your usual \(Int(usual.rounded())) ms: well recovered."
            }
        case .restingHR:
            switch HeartBands.restingHR(delta: d) {
            case .above, .wellBelow: return "\(Int(d.rounded())) beats above your usual: often short sleep, stress, alcohol or a bug coming on\(model.heartCycleCause)."
            case .usual: return "Right around your usual \(Int(usual.rounded())) bpm."
            case .below: return "Below your usual: a sign of good recovery."
            }
        case .sleep:
            let mins = Int((d * 60).rounded())
            if mins <= -45 { return "\(Clock.duration(-mins)) short of your \(Clock.duration(model.sleepNeed.minutes)) need. Adds to sleep debt." }
            if mins < -15 { return "A little short of your need." }
            return "Met your \(Clock.duration(model.sleepNeed.minutes)) need. Nice."
        }
    }

    /// The usual band: her own normal spread around the usual (one standard
    /// deviation), or a fixed ±12% / ±3 bpm / ±30 min until there is one.
    private var band: ClosedRange<Double> {
        switch metric {
        case .hrv:
            let pct = (model.hrvSpreadPct ?? 12) / 100
            return usual * (1 - pct)...usual * (1 + pct)
        case .restingHR:
            let sd = model.restingHRSpread ?? 3
            return (usual - sd)...(usual + sd)
        case .sleep:
            return (usual - 0.5)...(usual + 0.5)
        }
    }

    private var scale: NightTrendChart.Scale {
        switch metric {
        case .hrv: .percent(0.25)
        case .restingHR: .points(8)
        case .sleep: .points(2)
        }
    }

    private var dayFormat: Date.FormatStyle { .dateTime.weekday(.abbreviated).month(.abbreviated).day() }

    private var reference: String { metric == .sleep ? "your need" : "your usual" }

    /// The readout before she touches the chart: "30-night average · 46 ms",
    /// "Range 42–49 ms · your usual 46 ms"; on 6M the average of the weeks'
    /// nights and the range of the weekly averages. Nil with fewer than 2
    /// points.
    private func atRest(_ points: [NightTrendPoint]) -> (title: String, value: String, detail: String)? {
        let values = points.map(\.value)
        guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return nil }
        let nights = points.map(\.nights).reduce(0, +)
        let average = points.map { $0.value * Double($0.nights) }.reduce(0, +) / Double(nights)
        // "42–49 ms" (one unit) for HRV and resting HR; durations keep both.
        let spread = metric == .sleep ? "\(format(lo))\u{2013}\(format(hi))" : "\(Int(lo.rounded()))\u{2013}\(format(hi))"
        let title = range.isWeekly ? "6-month average" : "\(values.count)-night average"
        return (title, format(average), "\(range.isWeekly ? "Weekly averages" : "Range") \(spread) \u{00B7} \(reference) \(format(usual))")
    }

    /// A week on 6M: how many nights it averages, never a verdict meant for
    /// one night.
    private func detail(_ p: NightTrendPoint) -> String {
        range.isWeekly ? "Average of \(p.nights) nights \u{00B7} \(reference) \(format(usual))" : meaning(p.value)
    }

    private func title(_ p: NightTrendPoint) -> String {
        if range.isWeekly { return "Week of " + p.date.formatted(.dateTime.month(.abbreviated).day()) }
        let day = selected == nil ? "Last night \u{00B7} \(p.date.formatted(dayFormat))" : p.date.formatted(dayFormat)
        return model.isBreakDay(p.date) ? "\(day) \u{00B7} \(model.packBreakName)" : day
    }

    var body: some View {
        let points = points
        let rest = atRest(points)
        let shown = shown(in: points)
        let slots = points.map(detail)
        let breaks = model.breakSpans(in: range.domain())
        Card {
            if typeSize.isAccessibilitySize {
                ExplainedTitle(text: range.title, explanation: explanation, size: 17)
                TrendRangePicker(range: $range, accent: accent)
            } else {
                HStack {
                    ExplainedTitle(text: range.title, explanation: explanation, size: 17)
                    Spacer()
                    TrendRangePicker(range: $range, accent: accent)
                        .frame(maxWidth: 150)
                }
            }
            AdaptiveSegmentedPicker("Measure", selection: $metric, options: Array(Metric.allCases)) { m in m.rawValue }
                .onChange(of: metric) { _, _ in selected = nil }
            if selected == nil, let rest {
                // At rest, the period, not last night again: the screen's
                // summary already says that (F17).
                ChartReadout(title: rest.title, value: rest.value, detail: rest.detail, accent: accent,
                             detailSlots: slots)
            } else if let p = shown {
                ChartReadout(title: title(p), value: format(p.value), detail: detail(p),
                             accent: !range.isWeekly && isWorse(p.value) ? .coral : accent,
                             onClear: selected == nil ? nil : { selected = nil },
                             detailSlots: slots + [rest?.detail].compactMap { $0 })
            }
            if points.count >= 2 {
                NightTrendChart(points: points, range: range, usual: usual, band: band, scale: scale, accent: accent,
                                usualLabel: metric == .sleep ? "Your need" : "Your usual",
                                seriesName: metric.spoken, format: format, breaks: breaks,
                                selected: selected == nil ? nil : shown?.date, selection: $selected)
                    .frame(height: 170)
                    .motion(.dataSwap, value: metric)
                    .motion(.dataSwap, value: range)
                if !breaks.isEmpty {
                    ChartKey(items: [.init(label: model.packBreakName, mark: .band)])
                }
                ScrubHint(each: range.step)
            } else {
                Text(range.isWeekly ? "Not enough weeks yet." : "Not enough nights yet.").font(.bodyText).secondaryText()
            }
        }
        .onChange(of: range) { _, _ in selected = nil }
        .task(id: range) {
            if range == .sixMonths { older = await model.olderTrendNights() }
        }
    }
}

/// One night on a trend, or on 6M one week's average (`nights` is how many
/// nights it averages).
struct NightTrendPoint: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let value: Double
    var nights = 1
}

/// HRV, resting heart rate or sleep over recent nights or weeks, honestly scaled
/// (Tanaka F8, Valtonen F13): the y-axis spans her usual ±25% (HRV) or
/// ±8 bpm (resting HR), widened only when a night falls outside, so a
/// 3 ms wobble no longer looks like a cliff. Her usual band is shaded, each
/// night is a point on a straight-segment line, and the y-axis sits on the
/// leading edge so the latest night at the right isn't crowded.
struct NightTrendChart: View {
    enum Scale {
        /// usual × (1 ± fraction)
        case percent(Double)
        /// usual ± value
        case points(Double)
    }

    let points: [NightTrendPoint]
    var range: TrendRange = .month
    let usual: Double
    let band: ClosedRange<Double>?
    let scale: Scale
    let accent: Accent
    var usualLabel = "Your usual"
    var seriesName: String
    var format: (Double) -> String
    /// Her break weeks, shaded behind the nights (D-G3).
    var breaks: [ClosedRange<Date>] = []
    let selected: Date?
    @Binding var selection: Date?
    @Environment(\.colorScheme) private var scheme

    private var yDomain: ClosedRange<Double> {
        let half: Double
        switch scale {
        case .percent(let f): half = usual * f
        case .points(let v): half = v
        }
        let values = points.map(\.value)
        let lo = min(usual - half, (values.min() ?? usual) - half * 0.1)
        let hi = max(usual + half, (values.max() ?? usual) + half * 0.1)
        return max(lo, 0)...hi
    }

    /// "Usual" or "Need", short enough for the axis gutter.
    private var axisUsualLabel: String { usualLabel == "Your need" ? "Need" : "Usual" }

    private var summary: String {
        let values = points.map { format($0.value) }.joined(separator: ", ")
        let span = range.isWeekly ? "weekly averages over the last 6 months" : "the last \(points.count) nights"
        let shaded = breaks.isEmpty ? "" : " Shaded bands are your break weeks."
        return "\(seriesName), \(span), oldest first: \(values). \(usualLabel) is \(format(usual)).\(shaded)"
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        Chart {
            BreakWeekMarks(spans: breaks, scheme: scheme)
            if let band {
                RectangleMark(yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                    .foregroundStyle(p.track.opacity(scheme == .dark ? 0.8 : 0.7))
            }
            // Labelled in the trailing axis gutter, not on the plot: the
            // nights hover around her usual, so the label was drawn under
            // the line (Weber B).
            RuleMark(y: .value("Usual", usual))
                .foregroundStyle(p.tertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(points) { point in
                LineMark(x: .value("Night", point.date, unit: range.unit), y: .value(seriesName, point.value))
                    .foregroundStyle(accent.ink(scheme))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Night", point.date, unit: range.unit), y: .value(seriesName, point.value))
                    .foregroundStyle(accent.ink(scheme))
                    .symbolSize(20)
            }
            if let selected, let point = points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                RuleMark(x: .value("Night", point.date, unit: range.unit))
                    .foregroundStyle(p.tertiary)
                PointMark(x: .value("Night", point.date, unit: range.unit), y: .value(seriesName, point.value))
                    .foregroundStyle(accent.ink(scheme))
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: yDomain)
        // The whole range, so a missing night leaves a gap instead of
        // stretching the rest.
        .chartXScale(domain: range.domain(), range: .plotDimension(startPadding: 4, endPadding: 12))
        .chartXAxis {
            switch range {
            case .week:
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            case .month:
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            case .sixMonths:
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
            AxisMarks(position: .trailing, values: [usual]) { _ in
                AxisValueLabel(horizontalSpacing: Space.xs) {
                    Text(axisUsualLabel)
                        .font(.chartLabel(size: 10, weight: .semibold))
                        .foregroundStyle(p.secondary)
                }
            }
        }
        .chartScrub($selection, snapped: selected, steps: points.map(\.date))
        .accessibilityLabel(summary)
        .accessibilityChartDescriptor(DateChartDescriptor(
            title: range.isWeekly ? "\(seriesName), weekly averages, last 6 months" : "\(seriesName), last \(points.count) nights",
            seriesName: seriesName, yTitle: seriesName,
            points: points.map { ($0.date, $0.value) }, yLabel: format))
    }
}

/// HRV or resting heart rate on its own: this morning against her usual,
/// then the trend over a week, a month or six months. Opened from the Body tab's vitals and Recovery.
struct HeartMetricView: View {
    enum Metric { case hrv, restingHR }
    let metric: Metric
    @EnvironmentObject var model: AppModel

    private var title: String { metric == .hrv ? "HRV" : "Resting heart rate" }
    /// HRV indigo, resting HR pink, on the row, screen and chart (Tanaka F1).
    private var accent: Accent { metric == .hrv ? .indigo : .pink }

    private var value: String {
        guard model.hasHeartData else { return "No reading yet" }
        return metric == .hrv ? "\(Int(model.hrv.rounded())) ms" : "\(Int(model.restingHR.rounded())) bpm"
    }

    /// One sentence; the chart's readout under it says what can move it.
    private var change: String {
        guard model.hasHeartData else { return "Wear your Watch to bed. The first reading comes in after a night\u{2019}s sleep." }
        switch metric {
        case .hrv:
            let v = Int(model.hrvDeltaPct.rounded())
            switch model.hrvLevel {
            case .wellBelow: return "\(abs(v))% below your usual. Your body was under some strain."
            case .below: return "\(abs(v))% below your usual. Normal day-to-day wobble."
            case .usual: return "Right around your usual."
            case .above: return "\(v)% above your usual. Well recovered."
            }
        case .restingHR:
            let v = Int(model.restingHRDelta.rounded())
            switch model.restingHRLevel {
            case .above, .wellBelow: return "\(v) beats above your usual."
            case .usual: return "Right around your usual."
            case .below: return "\(abs(v)) beats below your usual. A sign of good recovery."
            }
        }
    }

    private var pairs: [StatPair] {
        guard model.hasHeartData else { return [] }
        var out = [StatPair(label: "Your usual", value: metric == .hrv ? "\(Int(model.baselineHRV.rounded())) ms"
                                                                        : "\(Int(model.baselineRestingHR.rounded())) bpm")]
        if metric == .hrv && model.hrvIsOvernight {
            out.append(StatPair(label: "Measured", value: "While you slept"))
        }
        return out
    }

    /// Only when her sleep is real but the heart readings aren't yet;
    /// otherwise the screen's Example data capsule already says so.
    private var status: SummaryStatus? {
        model.hasHeartData && !model.heartIsReal && !model.usingSampleData ? SummaryStatus(text: "Example", accent: .yellow) : nil
    }

    var body: some View {
        Screen(title: title, accent: accent) {
            SampleDataBanner()
            SummaryHeader(eyebrow: "This morning", value: value, status: status, line: change, pairs: pairs,
                          accent: accent, info: metric == .hrv ? model.hrvExplanation : model.restingHRExplanation)
            BodyTrendCard(metric: metric == .hrv ? .hrv : .restingHR)
        }
    }
}

/// The HRV and resting heart rate rows (for a `RowCard`): this morning's
/// value, the change from her usual and a trend arrow, each opening its
/// `HeartMetricView`. On the Body tab's vitals and on Recovery.
struct HeartMetricRows: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let heart = model.hasHeartData
        MetricRow(title: "HRV", note: heart ? hrvNote : "Wear your Watch to bed",
                  value: heart ? "\(Int(model.hrv.rounded())) ms" : nil, trend: heart ? hrvTrend : nil,
                  systemImage: "waveform.path.ecg", accent: .indigo) { HeartMetricView(metric: .hrv) }
        RowDivider()
        MetricRow(title: "Resting heart rate", note: heart ? restingHRNote : "Wear your Watch to bed",
                  value: heart ? "\(Int(model.restingHR.rounded())) bpm" : nil, trend: heart ? restingHRTrend : nil,
                  systemImage: "heart.fill", accent: .pink) { HeartMetricView(metric: .restingHR) }
    }

    private var hrvNote: String {
        let v = Int(model.hrvDeltaPct.rounded())
        if v == 0 { return "Right at your usual" }
        return "\(abs(v))% \(v > 0 ? "above" : "below") your usual"
    }

    private var hrvTrend: RowTrend? {
        let v = Int(model.hrvDeltaPct.rounded())
        guard v != 0 else { return nil }
        let tone: RowTrend.Tone = model.hrvLevel == .wellBelow ? .worse : model.hrvLevel == .above ? .better : .neutral
        return .init(up: v > 0, tone: tone)
    }

    private var restingHRNote: String {
        let v = Int(model.restingHRDelta.rounded())
        if v == 0 { return "Right at your usual" }
        return "\(abs(v)) bpm \(v > 0 ? "above" : "below") your usual"
    }

    private var restingHRTrend: RowTrend? {
        let v = Int(model.restingHRDelta.rounded())
        guard v != 0 else { return nil }
        let level = model.restingHRLevel
        let tone: RowTrend.Tone = level == .above || level == .wellBelow ? .worse : level == .below ? .better : .neutral
        return .init(up: v > 0, tone: tone)
    }
}
