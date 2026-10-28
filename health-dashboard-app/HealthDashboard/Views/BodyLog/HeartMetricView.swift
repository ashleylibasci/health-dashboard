import SwiftUI
import Charts
import HealthCore

// HRV and resting heart rate: the detail screen behind the Body tiles, the
// 14-night trend card (also on the Body tab) and the chart both share with
// Recovery. Moved out of BodyView.swift so the detail screens own them.

/// HRV, resting heart rate or sleep over the last 14 nights. Drag across it
/// to read any night against your usual.
struct BodyTrendCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var metric: Metric
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

    private var points: [NightTrendPoint] {
        model.bodyTrend.compactMap { t in
            switch metric {
            case .hrv: return t.hrv.map { NightTrendPoint(date: t.date, value: $0) }
            case .restingHR: return t.restingHR.map { NightTrendPoint(date: t.date, value: $0) }
            case .sleep: return NightTrendPoint(date: t.date, value: Double(t.asleep) / 60)
            }
        }
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

    private var shown: NightTrendPoint? {
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

    var body: some View {
        Card {
            HStack {
                ExplainedTitle(text: "Last 14 nights", explanation: explanation, size: 17)
                Spacer()
            }
            AdaptiveSegmentedPicker("Measure", selection: $metric, options: Array(Metric.allCases)) { m in m.rawValue }
                .onChange(of: metric) { _, _ in selected = nil }
            if let p = shown {
                ChartReadout(title: selected == nil ? "Last night \u{00B7} \(p.date.formatted(dayFormat))" : p.date.formatted(dayFormat),
                             value: format(p.value), detail: meaning(p.value),
                             accent: isWorse(p.value) ? .coral : accent,
                             onClear: selected == nil ? nil : { selected = nil },
                             detailSlots: points.map { meaning($0.value) })
            }
            if points.count >= 2 {
                NightTrendChart(points: points, usual: usual, band: band, scale: scale, accent: accent,
                                usualLabel: metric == .sleep ? "Your need" : "Your usual",
                                seriesName: metric.spoken, format: format,
                                selected: selected == nil ? nil : shown?.date, selection: $selected)
                    .frame(height: 170)
                    .motion(.dataSwap, value: metric)
                ScrubHint(each: "night")
            } else {
                Text("Not enough nights yet.").font(.bodyText).secondaryText()
            }
        }
    }
}

/// One night on a 14-night trend.
struct NightTrendPoint: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let value: Double
}

/// HRV, resting heart rate or sleep over recent nights, honestly scaled
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
    let usual: Double
    let band: ClosedRange<Double>?
    let scale: Scale
    let accent: Accent
    var usualLabel = "Your usual"
    var seriesName: String
    var format: (Double) -> String
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
        return "\(seriesName) for the last \(points.count) nights, oldest first: \(values). \(usualLabel) is \(format(usual))."
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        Chart {
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
                LineMark(x: .value("Night", point.date, unit: .day), y: .value(seriesName, point.value))
                    .foregroundStyle(accent.ink(scheme))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Night", point.date, unit: .day), y: .value(seriesName, point.value))
                    .foregroundStyle(accent.ink(scheme))
                    .symbolSize(20)
            }
            if let selected, let point = points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                RuleMark(x: .value("Night", point.date, unit: .day))
                    .foregroundStyle(p.tertiary)
                PointMark(x: .value("Night", point.date, unit: .day), y: .value(seriesName, point.value))
                    .foregroundStyle(accent.ink(scheme))
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(range: .plotDimension(startPadding: 4, endPadding: 12))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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
            title: "\(seriesName), last \(points.count) nights", seriesName: seriesName, yTitle: seriesName,
            points: points.map { ($0.date, $0.value) }, yLabel: format))
    }
}

/// HRV or resting heart rate on its own: today against her usual, the last
/// 14 nights, and how it feeds recovery. Opened from the Body tiles.
struct HeartMetricView: View {
    enum Metric { case hrv, restingHR }
    let metric: Metric
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    private var title: String { metric == .hrv ? "HRV" : "Resting heart rate" }
    /// HRV indigo, resting HR pink, on the tile, screen and chart (Tanaka F1).
    private var accent: Accent { metric == .hrv ? .indigo : .pink }

    private var value: String {
        guard model.hasHeartData else { return "No reading yet" }
        return metric == .hrv ? "\(Int(model.hrv.rounded())) ms" : "\(Int(model.restingHR.rounded())) bpm"
    }

    private var change: String {
        guard model.hasHeartData else { return "Wear your Watch to bed. The first reading comes in after a night\u{2019}s sleep." }
        switch metric {
        case .hrv:
            let v = Int(model.hrvDeltaPct.rounded())
            switch model.hrvLevel {
            case .wellBelow: return "\(abs(v))% below your usual. " + model.hrvMeaning(model.hrvDeltaPct)
            case .below: return "\(abs(v))% below your usual. Normal day-to-day wobble."
            case .usual: return "Right around your usual."
            case .above: return "\(v)% above your usual. Well recovered."
            }
        case .restingHR:
            let v = Int(model.restingHRDelta.rounded())
            switch model.restingHRLevel {
            case .above, .wellBelow: return "\(v) beats above your usual. Often short sleep, stress, alcohol or a bug coming on\(model.heartCycleCause)."
            case .usual: return "Right around your usual."
            case .below: return "\(abs(v)) beats below your usual. A sign of good recovery."
            }
        }
    }

    private var explanation: Explanation { metric == .hrv ? model.hrvExplanation : model.restingHRExplanation }

    var body: some View {
        Screen(title: title, accent: accent) {
            SampleDataBanner()
            Card {
                HStack(spacing: 0) {
                    SectionLabel(text: "This morning", accent: accent)
                    InfoButton(explanation: explanation).padding(.vertical, -12)
                    Spacer()
                    // Only when her sleep is real but the heart readings aren't yet;
                    // otherwise the screen's Example data capsule already says so.
                    if model.hasHeartData && !model.heartIsReal && !model.usingSampleData { ExampleTag() }
                }
                Text(value).font(model.hasHeartData ? .display : .detailTitle)
                    .contentTransition(.numericText())
                Text(change).font(.bodyText).fixedSize(horizontal: false, vertical: true)
                if model.hasHeartData && metric == .hrv && model.hrvIsOvernight {
                    Text("From readings taken while you slept.").font(.secondary).secondaryText()
                }
                HowWeGotThisLink(explanation: explanation)
            }
            BodyTrendCard(metric: metric == .hrv ? .hrv : .restingHR)
            Card(density: .compact) {
                LinkRow(title: "Recovery", subtitle: "How this and your other numbers add up today",
                        systemImage: "heart.fill", accent: .indigo) {
                    RecoveryView()
                }
            }
        }
    }
}
