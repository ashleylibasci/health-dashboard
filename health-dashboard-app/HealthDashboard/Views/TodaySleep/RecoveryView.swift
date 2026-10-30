import SwiftUI
import Charts
import HealthCore

/// Today's recovery, the last two weeks, and what moved it.
struct RecoveryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var selectedDay: Date? = nil

    var body: some View {
        Screen(title: "Recovery", accent: .indigo) {
            SampleDataBanner()
            header
            historyCard
            RowCard {
                ExpandRow(title: "What moved today", summary: movedSummary, systemImage: "arrow.left.arrow.right", accent: .indigo) {
                    movedContent
                }
                RowDivider()
                HeartMetricRows()
                RowDivider()
                // Does the score match how she felt? (H-E3)
                ExpandRow(title: "Does it match how you feel?", summary: model.scoreMatchSummary(model.recoveryMatch),
                          systemImage: "person.fill.questionmark", accent: .indigo) {
                    Text(model.scoreMatchDetail("recovery")).fixedSize(horizontal: false, vertical: true)
                }
                RowDivider()
                MetricRow(title: "Getting accurate numbers", note: "A checklist of ways to help your Watch",
                          systemImage: "checklist", accent: .indigo) {
                    AccuracyTipsView()
                }
            }
        }
    }

    // MARK: Header

    /// HRV, resting heart rate and last night, with the points each moved.
    private var effects: [(name: String, points: Int)] {
        [("lower HRV", model.recoveryPointsFromHRV),
         ("a higher resting heart rate", model.recoveryPointsFromRestingHR),
         ("a short night", model.recoveryPointsFromSleep)]
    }

    /// One sentence against her usual.
    private var summary: String {
        guard let score = model.recoveryShown else {
            return "No sleep from last night and no HRV or resting heart rate yet. Wear your Watch to bed tonight."
        }
        let usual = model.recoveryUsualPhrase
        let diff = score - model.recoveryUsual
        if diff <= -3 {
            if let worst = effects.min(by: { $0.points < $1.points }), worst.points < 0 {
                return "Below \(usual), mostly from \(worst.name)."
            }
            return "Below \(usual)."
        }
        if diff >= 3 { return "Above \(usual). Your body has recovered well." }
        return "Close to \(usual)."
    }

    /// What today's number is missing or allowing for, said where the
    /// inputs are (in "What moved today").
    private var caveats: String? {
        var parts: [String] = []
        if model.recoveryIsExample {
            parts.append("Example: until your Watch has learned your usual HRV and resting heart rate, example heart readings stand in.")
        } else if !model.hasHeartData {
            parts.append("No HRV or resting heart rate yet, so this is from sleep alone.")
        } else if !model.lastNightIsFresh {
            parts.append("No sleep was recorded last night, so this is from your heart readings only.")
        }
        if let cycle = model.recoveryCycleNote { parts.append(cycle) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var info: Explanation {
        let topic = Topic.recovery.explanation
        let method = "Recovery starts from a fixed starting score of \(AppModel.recoveryAnchor), chosen by the app (not a population average). Your HRV this morning compared with your last 30 days moves it most, then your resting heart rate, then how last night's sleep compared with your need. Each input is scored on its own, which is how we show how many points each one moved today. "
            + (model.heartFollowsCycle
               ? "With a natural cycle, the app expects resting heart rate about 1.5 beats higher and HRV about 4% lower in the second half of your cycle, and the reverse in the first 7 days from the start of your period, and takes that out before scoring. It only does this when it knows where you are in your cycle. "
               : "Your birth control stops ovulation, so your heart readings don't swing with a cycle and nothing is adjusted for one. ")
            + (model.recoveryUsualIsPersonal ? "Your usual, \(model.recoveryUsual), is your own average over recent days." : "Once you have 7 days of readings, your usual becomes your own average.")
        return Explanation(id: topic.id, title: topic.title, meaning: topic.meaning, forYou: topic.forYou, howWeGotIt: method)
    }

    /// This morning's heart readings against her usual.
    private var pairs: [StatPair] {
        guard model.recoveryShown != nil, model.hasHeartData else { return [] }
        return [StatPair(label: "HRV", value: SleepText.signed(model.hrvDeltaPct) + "%"),
                StatPair(label: "Resting HR", value: SleepText.signed(model.restingHRDelta) + " bpm")]
    }

    private var header: some View {
        let score = model.recoveryShown
        return SummaryHeader(eyebrow: "Recovery today", value: score.map { "\($0)" } ?? "No recovery yet",
                             // The screen's Example data capsule says so on example data.
                             unit: model.recoveryIsExample && !model.usingSampleData ? "example" : nil,
                             status: score.map { SummaryStatus(text: model.recoveryLabel(for: $0), accent: .indigo) },
                             line: summary, pairs: pairs, accent: .indigo,
                             info: info)
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
        let slots = history.map(nightDetail)
        if let night = nearestNight(history) {
            ChartReadout(title: "\(dayText(night.day)) \u{00B7} \(model.recoveryLabel(for: night.score))", value: "\(night.score)",
                         detail: nightDetail(night), accent: night.bedtime >= lateBedtime ? .coral : .indigo,
                         onClear: { selectedDay = nil }, detailSlots: slots)
        } else if let low = history.min(by: { $0.score < $1.score }) {
            ChartReadout(title: "Lowest day \u{00B7} \(dayText(low.day))", value: "\(low.score)",
                         detail: nightDetail(low), accent: .coral, detailSlots: slots)
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
                                     selected: nearestNight(history)?.day, selection: $selectedDay.snapping { d in
                                         history.min { abs($0.day.timeIntervalSince(d)) < abs($1.day.timeIntervalSince(d)) }?.day
                                     })
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

    // MARK: What moved

    /// "Mostly lower HRV", or what she compares against.
    private var movedSummary: String {
        if let worst = effects.min(by: { $0.points < $1.points }), worst.points < 0 {
            return "Most of all: \(worst.name)"
        }
        return "Against your last 4 weeks"
    }

    @ViewBuilder
    private var movedContent: some View {
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
        Text("Compared with your last 4 weeks.")
        MovedDrivers(rows: rows)
            .foregroundStyle(Palette(scheme: scheme).primary)
        Text("Bars to the left of the line pulled today down; bars to the right lifted it."
             + (model.hasHeartData && model.cycleHeartShift != .none ? " The bars allow for your cycle; the numbers are the raw change." : ""))
            .fixedSize(horizontal: false, vertical: true)
        if let caveats {
            Text(caveats).fixedSize(horizontal: false, vertical: true)
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

    /// One sentence for VoiceOver (D-A2); each day is in the audio graph.
    private var summary: String {
        let scores = history.map(\.score)
        guard let lo = scores.min(), let hi = scores.max(), let last = scores.last else { return "Recovery: no days yet." }
        let reference = usualLabel == "Start" ? "the starting point of \(usual)" : "your usual of \(usual)"
        return "Recovery for the last \(history.count) days: from \(lo) to \(hi), latest \(last), against \(reference)."
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
