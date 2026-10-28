import SwiftUI
import Charts
import HealthCore

/// Today's recovery, what moved it, and the last two weeks.
struct RecoveryView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedDay: Date? = nil
    @State private var heartMetric: HeartMetric = .hrv
    @State private var selectedHeartDay: Date? = nil

    var body: some View {
        Screen(title: "Recovery", accent: .indigo) {
            SampleDataBanner()
            heroCard
            historyCard
            movedCard
            heartCard
            Card(padding: 12) {
                LinkRow(title: "Getting accurate numbers", subtitle: "A checklist of ways to help your Watch",
                        systemImage: "checklist", accent: .indigo) {
                    AccuracyTipsView()
                }
            }
        }
    }

    // MARK: Hero

    private var summary: String {
        guard let score = model.recoveryShown else {
            return "No sleep from last night and no HRV or resting heart rate yet. Wear your Watch to bed tonight."
        }
        let usual = model.recoveryUsualPhrase
        let diff = score - model.recoveryUsual
        let effects: [(name: String, points: Int)] = [
            ("lower HRV", model.recoveryPointsFromHRV),
            ("a higher resting heart rate", model.recoveryPointsFromRestingHR),
            ("a short night", model.recoveryPointsFromSleep),
        ]
        var text: String
        if diff <= -3 {
            let worst = effects.min { $0.points < $1.points }
            if let worst, worst.points < 0 {
                text = "Below \(usual), mostly from \(worst.name)."
            } else {
                text = "Below \(usual)."
            }
        } else if diff >= 3 {
            text = "Above \(usual). Your body has recovered well."
        } else {
            text = "Close to \(usual)."
        }
        if model.recoveryIsExample {
            text += " Example: until your Watch has learned your usual HRV and resting heart rate, example heart readings stand in."
        } else if !model.hasHeartData {
            text += " No HRV or resting heart rate yet, so this is from sleep alone."
        } else if !model.lastNightIsFresh {
            text += " No sleep was recorded last night, so this is from your heart readings only."
        }
        if let cycle = model.recoveryCycleNote {
            text += " " + cycle
        }
        return text
    }

    private var heroCard: some View {
        Card {
            HStack(spacing: 0) {
                SectionLabel(text: "Recovery today")
                InfoButton(topic: .recovery).padding(.vertical, -14)
                Spacer()
            }
            .padding(.bottom, -8)
            VStack(spacing: 14) {
                if let score = model.recoveryShown {
                    Ring(value: Double(score) / 100, accent: .indigo, lineWidth: 18,
                         label: "\(score)", caption: model.recoveryLabel(for: score), size: 190,
                         accessibilityText: "Recovery \(score), \(model.recoveryLabel(for: score))")
                    if model.recoveryIsExample {
                        ExampleTag()
                    }
                } else {
                    Text("No recovery yet today").font(.scaled(size: 22, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                }
                Text(summary)
                    .font(.scaled(size: 15))
                    .multilineTextAlignment(.center)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                HowWeGotThisLink(title: "Recovery",
                                 method: "Recovery starts from a fixed starting score of \(AppModel.recoveryAnchor), chosen by the app (not a population average). Your HRV this morning compared with your last 30 days moves it most, then your resting heart rate, then how last night's sleep compared with your need. Each input is scored on its own, which is how we show how many points each one moved today. "
                                    + (model.heartFollowsCycle
                                       ? "With a natural cycle, the app expects resting heart rate about 1.5 beats higher and HRV about 4% lower in the second half of your cycle, and the reverse in the first 7 days from the start of your period, and takes that out before scoring. It only does this when it knows where you are in your cycle. "
                                       : "Your birth control stops ovulation, so your heart readings don't swing with a cycle and nothing is adjusted for one. ")
                                    + (model.recoveryUsualIsPersonal ? "Your usual, \(model.recoveryUsual), is your own average over recent days." : "Once you have 7 days of readings, your usual becomes your own average."))
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 14 days

    /// A bedtime at or after this counts as late (her usual + 90 min, or 2am).
    private var lateBedtime: Minutes { model.lateBedtimeThreshold }

    private func nearestNight(_ history: [AppModel.RecoveryNight]) -> AppModel.RecoveryNight? {
        guard let selectedDay else { return nil }
        return history.min { abs($0.day.timeIntervalSince(selectedDay)) < abs($1.day.timeIntervalSince(selectedDay)) }
    }

    private func dayText(_ day: Date) -> String {
        Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func nightDetail(_ night: AppModel.RecoveryNight) -> String {
        let usual = model.recoveryUsual
        let gap = night.score - usual
        let word = model.recoveryUsualIsPersonal ? "your usual" : "the starting point"
        let vs = abs(gap) < 3 ? "About \(word)." : gap < 0 ? "\(-gap) below \(word)." : "\(gap) above \(word)."
        let why = night.bedtime >= lateBedtime
            ? " Followed a \(Clock.format(night.bedtime)) bedtime."
            : " Slept \(Clock.duration(night.asleep))."
        return vs + why
    }

    @ViewBuilder
    private func historyReadout(_ history: [AppModel.RecoveryNight]) -> some View {
        if let night = nearestNight(history) {
            ChartReadout(title: dayText(night.day), value: "\(night.score) \u{00B7} \(model.recoveryLabel(for: night.score))",
                         detail: nightDetail(night), accent: night.bedtime >= lateBedtime ? .coral : .indigo)
        } else if let low = history.min(by: { $0.score < $1.score }) {
            ChartReadout(title: "Lowest day \u{00B7} \(dayText(low.day))", value: "\(low.score)",
                         detail: nightDetail(low), accent: .coral)
        }
    }

    @ViewBuilder
    private var historyCard: some View {
        let history = model.recoveryHistory(days: 14)
        if !history.isEmpty {
            Card {
                Text("Last \(history.count) days").font(.scaled(size: 17, weight: .bold))
                historyReadout(history)
                RecoveryHistoryChart(history: history, usual: model.recoveryUsual, lateBedtime: lateBedtime,
                                     selected: nearestNight(history)?.day, selection: $selectedDay)
                    .frame(height: 150)
                HStack {
                    Text(history.count > 1 ? "\(history.count - 1) days ago" : "")
                    Spacer()
                    Text("Today")
                }
                .font(.scaled(size: 11, weight: .semibold))
                .secondaryText()
                .accessibilityHidden(true)
                ScrubHint()
                Text(historyCaption(history))
                    .font(.scaled(size: 13))
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func historyCaption(_ history: [AppModel.RecoveryNight]) -> String {
        let usualText = model.recoveryUsualIsPersonal
            ? "The dashed line is your usual, \(model.recoveryUsual)."
            : "The dashed line is the starting point, \(model.recoveryUsual), until 7 days give your own usual."
        if history.contains(where: { $0.bedtime >= lateBedtime }) {
            return "Peach days followed a bedtime at \(Clock.format(lateBedtime)) or later. " + usualText
        }
        return usualText
    }

    // MARK: HRV and resting heart rate

    private var heartCard: some View {
        let history = model.heartTrend(days: 14)
        let points = history.compactMap { n -> HeartPoint? in
            guard let v = heartMetric == .hrv ? n.hrv : n.restingHR else { return nil }
            return HeartPoint(day: n.day, value: v)
        }
        let usual = heartMetric == .hrv ? model.baselineHRV : model.baselineRestingHR
        let selected = selectedHeartDay.flatMap { d in points.min { abs($0.day.timeIntervalSince(d)) < abs($1.day.timeIntervalSince(d)) } }
        return Card {
            HStack(spacing: 0) {
                Text("HRV and resting heart rate").font(.scaled(size: 17, weight: .bold))
                Spacer(minLength: 0)
                InfoButton(explanation: heartMetric == .hrv ? model.hrvExplanation : model.restingHRExplanation).padding(.vertical, -12)
            }
            HStack(spacing: 6) {
                ForEach(HeartMetric.allCases) { m in
                    Chip(title: m.label, selected: heartMetric == m, accent: .indigo) {
                        heartMetric = m
                        selectedHeartDay = nil
                    }
                }
            }
            if points.isEmpty {
                Text("Not enough mornings with \(heartMetric.label) yet. Wear your Watch to bed.")
                    .font(.scaled(size: 14))
                    .secondaryText()
            } else {
                heartReadout(selected: selected, latest: points.last, usual: usual)
                HeartTrendChart(points: points, usual: usual, metric: heartMetric, selected: selected?.day, selection: $selectedHeartDay)
                    .frame(height: 160)
                ScrubHint()
                Text(heartMetric == .hrv
                     ? "Higher than your usual (dashed line) means your body is relaxed and recovered."
                     : "Lower than your usual (dashed line) is better. \(Int(HeartBands.restingHRUp)) or more beats up can mean short sleep, stress, drinks or getting sick\(model.heartCycleCause).")
                    .font(.scaled(size: 13))
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func heartMeaning(_ value: Double, usual: Double) -> String {
        // The same bands and wording as Body (round 4, Brandt F8/F9).
        if heartMetric == .hrv {
            let pct = usual > 0 ? (value - usual) / usual * 100 : 0
            return "\(SleepText.signed(pct))% vs usual. " + model.hrvMeaning(pct)
        }
        let d = value - usual
        return "\(SleepText.signed(d)) bpm vs usual. " + model.restingHRMeaning(d)
    }

    @ViewBuilder
    private func heartReadout(selected: HeartPoint?, latest: HeartPoint?, usual: Double) -> some View {
        if let point = selected ?? latest {
            ChartReadout(title: selected == nil ? "Latest \u{00B7} \(dayText(point.day))" : dayText(point.day),
                         value: "\(Int(point.value.rounded())) \(heartMetric.unit)",
                         detail: heartMeaning(point.value, usual: usual),
                         accent: heartMetric == .hrv ? .indigo : .pink)
        }
    }

    // MARK: What moved

    private var movedCard: some View {
        let sleepGap = model.lastNight.asleep - model.sleepNeed.minutes
        return Card {
            HStack(alignment: .firstTextBaseline) {
                Text("What moved today").font(.scaled(size: 17, weight: .bold))
                Spacer()
                Text("vs your last 4 weeks").font(.scaled(size: 13)).secondaryText()
            }
            MovedRow(label: "HRV", valueText: model.hasHeartData ? SleepText.signed(model.hrvDeltaPct) + "%" : "No reading yet",
                     points: model.hasHeartData ? model.recoveryPointsFromHRV : 0,
                     explanation: model.hrvExplanation)
            MovedRow(label: "Resting HR", valueText: model.hasHeartData ? SleepText.signed(model.restingHRDelta) + " bpm" : "No reading yet",
                     points: model.hasHeartData ? model.recoveryPointsFromRestingHR : 0,
                     explanation: model.restingHRExplanation)
            MovedRow(label: "Sleep", valueText: model.lastNightIsFresh ? SleepText.signedCompact(sleepGap) : "None recorded",
                     points: model.lastNightIsFresh ? model.recoveryPointsFromSleep : 0,
                     explanation: Topic.sleepNeed.explanation)
            Text("Bars to the left of the line pulled today down; bars to the right lifted it."
                 + (model.hasHeartData && model.cycleHeartShift != .none ? " The bars allow for your cycle; the numbers are the raw change." : ""))
                .font(.scaled(size: 13))
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pieces

private struct RecoveryHistoryChart: View {
    let history: [AppModel.RecoveryNight]
    let usual: Int
    let lateBedtime: Minutes
    let selected: Date?
    @Binding var selection: Date?
    @Environment(\.colorScheme) private var scheme

    private var summary: String {
        let scores = history.map { "\($0.score)" }.joined(separator: ", ")
        return "Recovery for \(history.count) days, oldest first: \(scores). Usual is \(usual)."
    }

    private func color(_ night: AppModel.RecoveryNight) -> Color {
        let base = night.bedtime >= lateBedtime ? Accent.coral.fill(scheme) : Accent.indigo.fill(scheme)
        guard let selected else { return base }
        return Calendar.current.isDate(night.day, inSameDayAs: selected) ? base : base.opacity(0.35)
    }

    @ChartContentBuilder
    private var usualLine: some ChartContent {
        RuleMark(y: .value("Recovery", usual))
            .foregroundStyle(Palette(scheme: scheme).secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    var body: some View {
        Chart {
            ForEach(history) { night in
                BarMark(x: .value("Day", night.day, unit: .day), y: .value("Recovery", night.score))
                    .foregroundStyle(color(night))
                    .cornerRadius(4)
            }
            .accessibilityHidden(true)   // VoiceOver reads the summary (round 3, A9)
            usualLine.accessibilityHidden(true)
        }
        .chartScrub($selection)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100])
        }
        .accessibilityLabel(summary)
    }
}

private enum HeartMetric: String, CaseIterable, Identifiable {
    case hrv, restingHR
    var id: String { rawValue }
    var label: String { self == .hrv ? "HRV" : "Resting HR" }
    var unit: String { self == .hrv ? "ms" : "bpm" }
}

private struct HeartPoint: Identifiable, Hashable {
    var id: Date { day }
    let day: Date
    let value: Double
}

private struct HeartTrendChart: View {
    let points: [HeartPoint]
    let usual: Double
    let metric: HeartMetric
    let selected: Date?
    @Binding var selection: Date?
    @Environment(\.colorScheme) private var scheme

    private var accent: Accent { metric == .hrv ? .indigo : .pink }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value) + [usual]
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, 2)
        return (lo - pad)...(hi + pad)
    }

    private var summary: String {
        let values = points.map { "\(Int($0.value.rounded()))" }.joined(separator: ", ")
        return "\(metric.label) for \(points.count) mornings, oldest first: \(values) \(metric.unit). Usual is \(Int(usual.rounded()))."
    }

    @ChartContentBuilder
    private var usualLine: some ChartContent {
        RuleMark(y: .value(metric.label, usual))
            .foregroundStyle(Palette(scheme: scheme).secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let selected, let point = points.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
            RuleMark(x: .value("Day", point.day, unit: .day))
                .foregroundStyle(Palette(scheme: scheme).primary.opacity(0.3))
            PointMark(x: .value("Day", point.day, unit: .day), y: .value(metric.label, point.value))
                .foregroundStyle(accent.ink(scheme))
                .symbolSize(90)
        }
    }

    var body: some View {
        let line = accent.fill(scheme)
        Chart {
            // VoiceOver reads the chart's summary instead (round 3, A9).
            usualLine.accessibilityHidden(true)
            ForEach(points) { point in
                LineMark(x: .value("Day", point.day, unit: .day), y: .value(metric.label, point.value))
                    .foregroundStyle(line)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Day", point.day, unit: .day), y: .value(metric.label, point.value))
                    .foregroundStyle(line)
                    .symbolSize(24)
            }
            .accessibilityHidden(true)
            selectionMarks.accessibilityHidden(true)
        }
        .chartScrub($selection)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
        .accessibilityLabel(summary)
    }
}

/// A bar that grows left (pulled recovery down) or right (pushed it up)
/// from a center line.
private struct MovedRow: View {
    var label: String
    var valueText: String
    var points: Int
    var explanation: Explanation
    @Environment(\.colorScheme) private var scheme

    /// Ten points fills half the track.
    private var fraction: CGFloat { CGFloat(min(Double(abs(points)) / 10, 1)) }

    private var effectDescription: String {
        let n = abs(points) == 1 ? "1 point" : "\(abs(points)) points"
        if points < 0 { return "pulled recovery down \(n)" }
        if points > 0 { return "lifted recovery \(n)" }
        return "no change"
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        let accent: Accent = points < 0 ? .coral : .mint
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Text(label).font(.scaled(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                InfoButton(explanation: explanation).padding(.vertical, -14).padding(.horizontal, -10)
            }
            .frame(width: Font.scaledSize(104), alignment: .leading)
            GeometryReader { geo in
                let half = geo.size.width / 2
                let barWidth = max(points == 0 ? 0 : 4, half * fraction)
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track).frame(height: 10)
                    Capsule().fill(accent.fill(scheme))
                        .frame(width: barWidth, height: 10)
                        .offset(x: points < 0 ? half - barWidth : half)
                    Rectangle().fill(p.secondary).frame(width: 2, height: 18).offset(x: half - 1)
                }
                .frame(width: geo.size.width, height: 18)
            }
            .frame(height: 18)
            Text(valueText).font(.scaled(size: 14, weight: .bold)).frame(width: Font.scaledSize(64), alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label) \(valueText), \(effectDescription)")
    }
}
