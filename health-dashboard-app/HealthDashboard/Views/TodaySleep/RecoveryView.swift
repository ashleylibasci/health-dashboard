import SwiftUI
import Charts
import HealthCore

/// Today's recovery, what moved it, and the last two weeks.
struct RecoveryView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
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
            Card(density: .compact) {
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
                         label: "\(score)", caption: model.recoveryLabel(for: score), size: 208,
                         accessibilityText: "Recovery \(score), \(model.recoveryLabel(for: score))")
                    if model.recoveryIsExample {
                        ExampleTag()
                    }
                } else {
                    Text("No recovery yet today").font(.heading)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(summary)
                    .font(.bodyText)
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
            ChartReadout(title: "\(dayText(night.day)) \u{00B7} \(model.recoveryLabel(for: night.score))", value: "\(night.score)",
                         detail: nightDetail(night), accent: night.bedtime >= lateBedtime ? .coral : .indigo,
                         onClear: { selectedDay = nil })
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
                Text("Last \(history.count) days").font(.cardTitle)
                historyReadout(history)
                RecoveryHistoryChart(history: history, usual: model.recoveryUsual,
                                     usualLabel: model.recoveryUsualIsPersonal ? "Usual" : "Start",
                                     lateBedtime: lateBedtime,
                                     selected: nearestNight(history)?.day, selection: $selectedDay)
                    .frame(height: 150)
                HStack {
                    Text(history.count > 1 ? "\(history.count - 1) days ago" : "")
                    Spacer()
                    Text("Today")
                }
                .font(.small).fontWeight(.semibold)
                .secondaryText()
                .accessibilityHidden(true)
                ScrubHint(each: "day")
                Text(historyCaption(history))
                    .font(.secondary)
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

    private var heartPoints: [NightTrendPoint] {
        model.heartTrend(days: 14).compactMap { n -> NightTrendPoint? in
            guard let v = heartMetric == .hrv ? n.hrv : n.restingHR else { return nil }
            return NightTrendPoint(date: n.day, value: v)
        }
    }

    private var heartUsual: Double { heartMetric == .hrv ? model.baselineHRV : model.baselineRestingHR }

    /// Her usual spread (one standard deviation), or ±12% / ±3 bpm until
    /// there's enough to know it.
    private var heartBand: ClosedRange<Double> {
        let usual = heartUsual
        if heartMetric == .hrv {
            let pct = (model.hrvSpreadPct ?? 12) / 100
            return usual * (1 - pct)...usual * (1 + pct)
        }
        let sd = model.restingHRSpread ?? 3
        return (usual - sd)...(usual + sd)
    }

    private func heartFormat(_ v: Double) -> String { "\(Int(v.rounded())) \(heartMetric.unit)" }

    private var heartCard: some View {
        let points = heartPoints
        let usual = heartUsual
        let selected = selectedHeartDay.flatMap { d in points.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }
        return Card {
            HStack(spacing: 0) {
                Text("HRV and resting heart rate").font(.cardTitle)
                Spacer(minLength: 0)
                InfoButton(explanation: heartMetric == .hrv ? model.hrvExplanation : model.restingHRExplanation).padding(.vertical, -12)
            }
            HStack(spacing: 6) {
                ForEach(HeartMetric.allCases) { m in
                    Chip(title: m.label, selected: heartMetric == m, accent: m == .hrv ? .indigo : .pink) {
                        heartMetric = m
                        selectedHeartDay = nil
                    }
                }
            }
            if points.isEmpty {
                Text("Not enough mornings with \(heartMetric.label) yet. Wear your Watch to bed.")
                    .font(.bodyText)
                    .secondaryText()
            } else {
                heartReadout(selected: selected, latest: points.last, usual: usual,
                             slots: points.map { heartMeaning($0.value, usual: usual) })
                NightTrendChart(points: points, usual: usual, band: heartBand,
                                scale: heartMetric == .hrv ? .percent(0.25) : .points(8),
                                accent: heartMetric == .hrv ? .indigo : .pink,
                                seriesName: heartMetric == .hrv ? "HRV" : "Resting heart rate",
                                format: heartFormat, selected: selected?.date, selection: $selectedHeartDay)
                    .frame(height: 170)
                    .motion(.dataSwap, value: heartMetric)
                ScrubHint(each: "morning")
                Text(heartMetric == .hrv
                     ? "Higher than your usual (dashed line) means your body is relaxed and recovered. The shaded band is your normal range."
                     : "Lower than your usual (dashed line) is better. \(Int(HeartBands.restingHRUp)) or more beats up can mean short sleep, stress, drinks or getting sick\(model.heartCycleCause). The shaded band is your normal range.")
                    .font(.secondary)
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

    /// Coral only for a reading worth acting on (Valtonen F4).
    private func heartIsWorse(_ value: Double, usual: Double) -> Bool {
        if heartMetric == .hrv {
            let pct = usual > 0 ? (value - usual) / usual * 100 : 0
            return HeartBands.hrv(deltaPct: pct, spreadPct: model.hrvSpreadPct) == .wellBelow
        }
        let level = HeartBands.restingHR(delta: value - usual)
        return level == .above || level == .wellBelow
    }

    @ViewBuilder
    private func heartReadout(selected: NightTrendPoint?, latest: NightTrendPoint?, usual: Double, slots: [String]) -> some View {
        if let point = selected ?? latest {
            ChartReadout(title: selected == nil ? "Latest \u{00B7} \(dayText(point.date))" : dayText(point.date),
                         value: heartFormat(point.value),
                         detail: heartMeaning(point.value, usual: usual),
                         accent: heartIsWorse(point.value, usual: usual) ? .coral : (heartMetric == .hrv ? .indigo : .pink),
                         onClear: selected == nil ? nil : { selectedHeartDay = nil },
                         detailSlots: slots)
        }
    }

    // MARK: What moved

    private var movedCard: some View {
        let sleepGap = model.lastNight.asleep - model.sleepNeed.minutes
        let sleepText = SleepText.signedCompact(sleepGap)
        let rows = [
            MovedDriver(label: "HRV", spoken: "HRV",
                        valueText: model.hasHeartData ? SleepText.signed(model.hrvDeltaPct) + "%" : "No reading yet",
                        spokenValue: model.hasHeartData ? SleepText.signed(model.hrvDeltaPct) + " percent" : "No reading yet",
                        points: model.hasHeartData ? model.recoveryPointsFromHRV : 0,
                        explanation: model.hrvExplanation),
            MovedDriver(label: "Resting HR", spoken: "Resting heart rate",
                        valueText: model.hasHeartData ? SleepText.signed(model.restingHRDelta) + " bpm" : "No reading yet",
                        spokenValue: model.hasHeartData ? SleepText.signed(model.restingHRDelta) + " beats a minute" : "No reading yet",
                        points: model.hasHeartData ? model.recoveryPointsFromRestingHR : 0,
                        explanation: model.restingHRExplanation),
            MovedDriver(label: "Sleep", spoken: "Sleep",
                        valueText: model.lastNightIsFresh ? sleepText : "None recorded",
                        spokenValue: model.lastNightIsFresh ? sleepText.replacingOccurrences(of: "\u{2212}", with: "minus ") : "None recorded",
                        points: model.lastNightIsFresh ? model.recoveryPointsFromSleep : 0,
                        explanation: Topic.sleepNeed.explanation),
        ]
        return Card {
            AdaptiveStack(spacing: Space.xs, alignment: .firstTextBaseline) {
                Text("What moved today").font(.cardTitle)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("vs your last 4 weeks").font(.secondary).secondaryText()
            }
            MovedDrivers(rows: rows)
            Text("Bars to the left of the line pulled today down; bars to the right lifted it."
                 + (model.hasHeartData && model.cycleHeartShift != .none ? " The bars allow for your cycle; the numbers are the raw change." : ""))
                .font(.secondary)
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pieces

private struct RecoveryHistoryChart: View {
    let history: [AppModel.RecoveryNight]
    let usual: Int
    /// The dashed line's name in the axis gutter: "Usual", or "Start" (the
    /// starting point) until there are 7 days.
    let usualLabel: String
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
            usualLine
        }
        // One VoiceOver element with the summary (chartScrub), so no
        // mark-level hiding (Weber A8).
        .chartScrub($selection, snapped: selected, steps: history.map(\.day).sorted())
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100])
            // The dashed line's name, in the gutter where no bar reaches (Weber B).
            AxisMarks(position: .trailing, values: [usual]) { _ in
                AxisValueLabel(horizontalSpacing: Space.xs) {
                    Text(usualLabel)
                        .font(.chartLabel(size: 10, weight: .semibold))
                        .foregroundStyle(Palette(scheme: scheme).secondary)
                }
            }
        }
        .accessibilityLabel(summary)
        .accessibilityChartDescriptor(DateChartDescriptor(
            title: "Recovery, last \(history.count) days", seriesName: "Recovery", yTitle: "Recovery",
            points: history.map { ($0.day, Double($0.score)) }, yLabel: { "\(Int($0.rounded()))" }, isContinuous: false))
    }
}

private enum HeartMetric: String, CaseIterable, Identifiable {
    case hrv, restingHR
    var id: String { rawValue }
    var label: String { self == .hrv ? "HRV" : "Resting HR" }
    var unit: String { self == .hrv ? "ms" : "bpm" }
}

/// One row of "What moved today".
private struct MovedDriver: Identifiable {
    var id: String { label }
    var label: String
    var spoken: String
    var valueText: String
    var spokenValue: String
    var points: Int
    var explanation: Explanation

    /// Ten points fills half the track.
    var fraction: CGFloat { CGFloat(min(Double(abs(points)) / 10, 1)) }

    var effectDescription: String {
        let n = abs(points) == 1 ? "1 point" : "\(abs(points)) points"
        if points < 0 { return "pulled recovery down \(n)" }
        if points > 0 { return "lifted recovery \(n)" }
        return "no change"
    }

    var accessibilityText: String { "\(spoken), \(spokenValue), \(effectDescription)" }
}

/// Bars that grow left (pulled recovery down) or right (lifted it) from a
/// centre line. A grid at standard sizes, so the label and value columns
/// take only the room their text needs and every centre line lines up; at
/// accessibility sizes, label and value on one line with the bar full width
/// below (Ortiz B1: fixed columns pushed the screen sideways). Each row is
/// one VoiceOver element, and its ⓘ is an "Explain" action (Ortiz F8/F9).
private struct MovedDrivers: View {
    var rows: [MovedDriver]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var explaining: Explanation? = nil

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.l) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: Space.s) {
                            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                                label(row)
                                Spacer(minLength: Space.s)
                                value(row)
                            }
                            bar(row)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.accessibilityText)
                        .accessibilityAction(named: "Explain") { explaining = row.explanation }
                    }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: Space.m) {
                    ForEach(rows) { row in
                        GridRow {
                            label(row)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(row.accessibilityText)
                                .accessibilityAction(named: "Explain") { explaining = row.explanation }
                            bar(row).accessibilityHidden(true)
                            value(row)
                                .gridColumnAlignment(.trailing)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .sheet(item: $explaining) { ExplanationSheet(explanation: $0) }
    }

    private func label(_ row: MovedDriver) -> some View {
        HStack(spacing: 0) {
            Text(row.label).font(.bodyEmphasis)
                .fixedSize(horizontal: false, vertical: true)
            Button { explaining = row.explanation } label: {
                Image(systemName: "info.circle")
                    .font(.secondary).fontWeight(.semibold)
                    .foregroundStyle(Palette(scheme: scheme).tertiary)
                    .frame(width: Sizes.minTap, height: Sizes.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -14).padding(.horizontal, -8)
            .accessibilityHidden(true)
        }
    }

    private func value(_ row: MovedDriver) -> some View {
        Text(row.valueText).font(.bodyEmphasis).fontWeight(.bold)
            .lineLimit(1)
            .fixedSize()
    }

    private func bar(_ row: MovedDriver) -> some View {
        let p = Palette(scheme: scheme)
        // Coral when it pulled recovery down, mint when it lifted it.
        let accent: Accent = row.points < 0 ? .coral : .mint
        return GeometryReader { geo in
            let half = geo.size.width / 2
            let barWidth = max(row.points == 0 ? 0 : 4, half * row.fraction)
            ZStack(alignment: .leading) {
                Capsule().fill(p.track).frame(height: 10)
                Capsule().fill(accent.fill(scheme))
                    .frame(width: barWidth, height: 10)
                    .offset(x: row.points < 0 ? half - barWidth : half)
                    .motion(.fill, value: row.points)
                Rectangle().fill(p.secondary).frame(width: 2, height: 18).offset(x: half - 1)
            }
            .frame(width: geo.size.width, height: 18)
        }
        .frame(minWidth: 80, maxWidth: .infinity)
        .frame(height: 18)
    }
}
