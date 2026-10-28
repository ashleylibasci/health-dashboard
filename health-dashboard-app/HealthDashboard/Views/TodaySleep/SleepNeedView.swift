import SwiftUI
import Charts
import HealthCore

/// How much sleep she needs, what it means for her, and tonight's target.
/// The method lives behind "Learn how we got this number".
struct SleepNeedView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    // HRV first: it comes straight from her Watch. The energy score is
    // only there when the app has one for that day.
    @State private var metric: NeedMetric = .hrv
    @State private var selectedHours: Double? = nil
    @State private var explaining: Explanation? = nil

    var body: some View {
        let need = model.sleepNeed
        Screen(title: "Your sleep need", accent: .purple) {
            SampleDataBanner()
            heroCard(need)
            tonightCard
            responseCard(need)
            feelingCard
            accuracyCard
            adjustCard(need)
            Text("An estimate from your own data, not a medical test. If you often need more than 10 hours or feel exhausted however long you sleep, talk to a doctor.")
                .font(.secondary)
                .secondaryText()
                .padding(.horizontal, 4)
        }
        .sheet(item: $explaining) { ExplanationSheet(explanation: $0) }
    }

    // MARK: Hero

    private func confidenceText(_ need: SleepNeedEstimate) -> (String, Accent) {
        switch need.confidence {
        case .learning: return ("Still learning", .yellow)
        case .fair: return ("Fairly sure", .mint)
        case .good: return ("Confident", .mint)
        }
    }

    private func needNote(_ need: SleepNeedEstimate) -> String {
        let adj = store.data.sleepNeedAdjustment
        if adj != 0 {
            return "You adjusted this by \(SleepText.signed(Double(adj))) min. We'll keep checking it against your data."
        }
        var text: String
        if need.minutes < 420 {
            text = "A little under the 7 to 9 hours most adults need."
        } else if need.minutes > 540 {
            text = "A little over the 7 to 9 hours most adults need."
        } else {
            text = "Right in the middle for adults, who mostly need 7 to 9 hours."
        }
        if let avg = model.alarmNightAverageAsleep {
            if avg < need.minutes - 10 {
                text += " You average \(Clock.duration(avg)) on school nights, so you run a little short most weeks."
            } else {
                text += " You average \(Clock.duration(avg)) on school nights, about what you need."
            }
        }
        return text
    }

    private func heroCard(_ need: SleepNeedEstimate) -> some View {
        let p = Palette(scheme: scheme)
        let (word, badgeAccent) = confidenceText(need)
        let example = model.sleepNeedIsExample
        let badgeText = example
            ? "Example \u{00B7} \(min(model.realNightCount, AppModel.nightsNeeded)) of \(AppModel.nightsNeeded) nights"
            : "\(word) \u{00B7} \(model.sleepNeedNightsUsed) nights"
        let badge = HStack(spacing: 5) {
            Image(systemName: example ? "hourglass" : "checkmark").font(.small).fontWeight(.bold).accessibilityHidden(true)
            Text(badgeText).font(.secondary).fontWeight(.bold)
        }
        .foregroundStyle((example ? Accent.yellow : badgeAccent).onTint(scheme))
        .padding(.horizontal, 10)
        .frame(minHeight: Font.scaledSize(26))
        .background((example ? Accent.yellow : badgeAccent).tint(scheme), in: Capsule())
        let title = HStack(spacing: 0) {
            SectionLabel(text: "Your body needs", accent: .purple)
            InfoButton(topic: .sleepNeed).padding(.vertical, -14)
        }
        return Card(accent: .purple) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    title
                    Spacer()
                    badge
                }
                VStack(alignment: .leading, spacing: 6) {
                    title
                    badge
                }
            }
            if example {
                Text("Example until \(AppModel.nightsNeeded) nights (\(min(model.realNightCount, AppModel.nightsNeeded)) of \(AppModel.nightsNeeded) so far). After that it's learned from your own nights.")
                    .font(.secondary)
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Clock.duration(need.minutes))
                    .font(.displayXL)
                    .tracking(-1)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("a night").font(.bodyEmphasis).foregroundStyle(p.secondary)
            }
            .accessibilityElement(children: .combine)
            HowWeGotThisLink(title: "Your sleep need", method: methodText(need))
            NeedRangeBar(need: need.minutes, range: need.range)
            Text("Purple band: the range of the clues, \(Clock.duration(need.range.start)) to \(Clock.duration(need.range.end)). Grey band: the 7 to 9 hours most adults need.")
                .font(.secondary)
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(needNote(need))
                .font(.bodyText)
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Tonight

    private func partLabel(_ part: TonightNeed.Part) -> String {
        if part.label == "Paying back sleep debt", model.sleepDebt > 0 {
            return "\(part.label) (\(Clock.duration(model.sleepDebt)))"
        }
        return part.label
    }

    /// The same sentence Today shows (`tonightShortNote`), from the one plan.
    private func planSentence(_ plan: WakePlan) -> String {
        if let short = model.tonightShortNote { return short + " The rest goes onto your sleep debt." }
        return "\(model.tonightBedUpLine): about \(Clock.duration(plan.asleep)) asleep, which covers it."
    }

    private func partTopic(_ part: TonightNeed.Part) -> Topic? {
        let label = part.label.lowercased()
        if label.contains("debt") { return .sleepDebt }
        if label.contains("period") { return .tonightNeed }
        if label.contains("fighting") { return .illness }
        if label.contains("base") { return .sleepNeed }
        return nil
    }

    private var tonightCard: some View {
        let p = Palette(scheme: scheme)
        let tonight = model.tonightNeed
        let plan = model.wakePlan()
        return Card {
            HStack(alignment: .firstTextBaseline) {
                ExplainedTitle(text: "Tonight you need", topic: .tonightNeed)
                Spacer()
                Text(model.tonightNeedText).font(.numberM)
            }
            ForEach(Array(tonight.parts.enumerated()), id: \.offset) { index, part in
                let topic = partTopic(part)
                HStack(spacing: 0) {
                    Text(partLabel(part)).font(.bodyText).foregroundStyle(p.secondary)
                    if let topic {
                        InfoButton(topic: topic).padding(.vertical, -14)
                            .accessibilityHidden(true)
                    }
                    Spacer()
                    // Additions are part of the plan, not a warning: no coral
                    // (Valtonen F4).
                    Text(index == 0 ? Clock.duration(part.minutes) : SleepText.signedCompact(part.minutes))
                        .font(.bodyEmphasis)
                        .foregroundStyle(index == 0 ? p.primary : p.secondary)
                }
                // Label and value read together, the ⓘ as an action (Ortiz F8, F9).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(partLabel(part)), \(index == 0 ? Clock.duration(part.minutes) : (part.minutes < 0 ? "minus " : "plus ") + Clock.duration(abs(part.minutes)))")
                .accessibilityAction(named: "Explain") { if let topic { explaining = topic.explanation } }
            }
            if let plan {
                Text(planSentence(plan))
                    .font(.bodyText)
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NavigationLink {
                WakePlanView()
            } label: {
                HStack(spacing: 6) {
                    Text("See tonight's wake plan").font(.bodyEmphasis)
                    Image(systemName: "chevron.right").font(.secondary).fontWeight(.bold).accessibilityHidden(true)
                }
                .foregroundStyle(Accent.purple.ink(scheme))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Dose-response chart

    private var dosePoints: [DosePoint] {
        let selected = metric
        return model.nights.enumerated().compactMap { pair -> DosePoint? in
            guard let value = selected.value(pair.element.outcome) else { return nil }
            return DosePoint(id: pair.offset, day: pair.element.wakeDay, hours: Double(pair.element.asleepMinutes) / 60, value: value)
        }
    }

    private func kneeFit(_ points: [DosePoint]) -> KneeFit? {
        let input: [(minutes: Double, value: Double)] = points.map { (minutes: $0.hours * 60, value: $0.value) }
        return SleepNeedEstimator.fitKnee(input, higherIsBetter: metric.higherIsBetter)
    }

    private func insight(_ fit: KneeFit?, need: SleepNeedEstimate) -> String {
        guard let fit else {
            return "Not enough nights with \(metric.noun) yet to see where more sleep stops helping. Keep wearing your Watch to bed."
        }
        let knee = Clock.duration(Int(fit.knee))
        let slope = Int(abs(fit.slopePerHour).rounded())
        switch metric {
        case .energy:
            return "Next-day energy climbs with every extra half hour until about \(knee), then flattens. That knee is your need."
        case .hrv:
            return "Each hour short of \(knee) costs about \(slope)% of your next-day HRV. Past \(knee) it stops improving."
        case .restingHR:
            return "Each hour under \(knee) adds about \(slope) \(slope == 1 ? "beat" : "beats") to your resting heart rate the next day."
        case .felt:
            let gap = need.minutes - Int(fit.knee)
            if gap >= 20 {
                return "Your check-ins level off at about \(knee), \(Clock.duration(gap)) before your body does. You stop noticing a short night before your body stops paying for it."
            }
            return "Your check-ins level off at about \(knee), close to where your body does."
        }
    }

    private func nearestDose(_ points: [DosePoint]) -> DosePoint? {
        guard let selectedHours else { return nil }
        return points.min { abs($0.hours - selectedHours) < abs($1.hours - selectedHours) }
    }

    /// A short value for the readout's big number, then what it is
    /// (Hale F8): "63 · energy score next day".
    private func valueText(_ value: Double) -> String {
        switch metric {
        case .energy: return "\(Int(value.rounded())) \u{00B7} energy score next day"
        case .hrv: return "\(SleepText.signed(value))% \u{00B7} HRV vs usual"
        case .restingHR: return "\(SleepText.signed(value, decimals: 1)) bpm \u{00B7} resting heart rate"
        case .felt: return String(format: "%.1f", value) + " of 5 \u{00B7} how you felt"
        }
    }

    private func doseDetail(_ point: DosePoint, fit: KneeFit?) -> String {
        guard let fit else { return "One night: how long you slept and how the next day went." }
        let gap = Int(fit.knee) - Int((point.hours * 60).rounded())
        if gap > 20 {
            return "\(Clock.duration(gap)) short of where more sleep stops helping. More sleep that night would likely have helped."
        }
        if gap < -20 {
            return "Past the point where more sleep helps, so the extra time didn't add much."
        }
        return "Right around your need: the sweet spot."
    }

    @ViewBuilder
    private func doseReadout(_ points: [DosePoint], fit: KneeFit?) -> some View {
        if let point = nearestDose(points) {
            ChartReadout(title: "\(point.day.formatted(.dateTime.month(.abbreviated).day())) \u{00B7} \(Clock.duration(Int((point.hours * 60).rounded()))) asleep",
                         value: valueText(point.value), detail: doseDetail(point, fit: fit), accent: metric.accent,
                         onClear: { selectedHours = nil })
        } else if let fit {
            // At rest: the answer, not a "touch" hint (Valtonen F13).
            ChartReadout(title: "Where more sleep stops helping", value: Clock.duration(Int(fit.knee)),
                         detail: "From \(points.count) nights of \(metric.noun). Nights to the left of the dashed line cost you the next day.",
                         accent: metric.accent)
        } else {
            ChartReadout(title: "\(points.count) nights", value: metric.label,
                         detail: "Not enough nights yet to see where more sleep stops helping.", accent: metric.accent)
        }
    }

    private func responseCard(_ need: SleepNeedEstimate) -> some View {
        let p = Palette(scheme: scheme)
        let points = dosePoints
        let fit = kneeFit(points)
        let insightAccent: Accent = metric == .felt ? .yellow : .purple
        return Card {
            ExplainedTitle(text: "How your body responds to sleep",
                           explanation: Explanation(id: "doseResponse", title: "How your body responds to sleep",
                                                    meaning: "Each dot is one of your nights: how long you slept (across) and how your body did the next day (up and down). The line shows the pattern, and the dashed line is where more sleep stops making a difference.",
                                                    forYou: "That point is your sleep need. Nights to the left of it cost you the next day, even if you felt fine."),
                           size: 17)
            Text("Each dot is one night: how long you slept, and what your body did the next day.")
                .font(.bodyText)
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { metricChips }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    metricChips
                }
            }
            doseReadout(points, fit: fit)
            DoseResponseChart(points: points, fit: fit, metric: metric, needRange: need.range,
                              selected: nearestDose(points), selection: $selectedHours)
                .frame(height: 220)
                .motion(.dataSwap, value: metric)
            ScrubHint(each: "night")
            Text(insight(fit, need: need))
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(insightAccent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        }
    }

    private var metricChips: some View {
        ForEach(NeedMetric.allCases) { m in
            Chip(title: m.label, selected: metric == m, accent: .purple) {
                metric = m
                selectedHours = nil
            }
        }
    }

    // MARK: Feeling fine

    private var feelingCard: some View {
        let p = Palette(scheme: scheme)
        let short = model.nights.filter { $0.asleepMinutes <= 390 }
        let felt = short.compactMap { $0.outcome.checkIn }.mean
        let hrv = short.compactMap { $0.outcome.hrvDeltaPct }.mean
        let rhr = short.compactMap { $0.outcome.restingHRDelta }.mean
        let hasStats = felt != nil || hrv != nil
        let study = "After short nights, people often feel nearly normal while their body is still paying for it. That's why the app trusts your body's numbers more than how you feel."
        return Card {
            ExplainedTitle(text: "Feeling fine isn't the whole story",
                           explanation: Explanation(id: "feelingFine", title: "Feeling fine after short sleep",
                                                    meaning: "When you sleep less than you need for several nights, you get used to the tired feeling. Your body and focus keep slipping even though you stop noticing.",
                                                    forYou: "Don't judge your sleep only by how you feel. If your HRV or energy dips after short nights, the short nights are costing you."),
                           size: 17)
            if hasStats {
                HStack(spacing: 8) {
                    if let felt {
                        FeelStat(title: "You felt", value: String(format: "%.1f/5", felt),
                                 note: felt >= 3.3 ? "almost normal" : "a bit rough", accent: .yellow)
                    }
                    if let hrv {
                        FeelStat(title: "HRV", value: SleepText.signed(hrv) + "%", note: hrv < 0 ? "lower" : "higher", accent: .indigo)
                    }
                    if let rhr {
                        FeelStat(title: "Resting HR", value: SleepText.signed(rhr), note: rhr > 0 ? "higher" : "lower", accent: .pink)
                    }
                }
            }
            Text((hasStats ? "That's you after a night of 6h 30m or less. " : "") + study)
                .font(.bodyText)
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Method (behind the link)

    private func methodName(_ kind: SleepNeedEstimate.Method.Kind) -> String {
        switch kind {
        case .rebound: return "Nights with no alarm (a clue that tends to run high)"
        case .hrv: return "Where more sleep stops helping your HRV"
        case .restingHR: return "Where more sleep stops lowering your resting heart rate"
        case .energy: return "Where more sleep stops lifting your energy"
        case .reaction: return "Where more sleep stops speeding up your reaction time"
        case .checkIn: return "Your morning check-ins (a light cross-check)"
        case .prior: return "The adult average of about 8 hours"
        }
    }

    private func methodText(_ need: SleepNeedEstimate) -> String {
        let total = need.methods.map(\.weight).reduce(0, +)
        var text = model.sleepNeedIsExample
            ? "For now this comes from example nights; it switches to yours after \(AppModel.nightsNeeded) nights (\(min(model.realNightCount, AppModel.nightsNeeded)) so far). We combine a few clues, each weighted by how much data backs it:"
            : "We combine a few clues from your own \(model.sleepNeedNightsUsed) nights, each weighted by how much data backs it:"
        for method in need.methods {
            let pct = total > 0 ? Int((method.weight / total * 100).rounded()) : 0
            text += "\n\u{2022} \(methodName(method.kind)): \(Clock.duration(method.minutes)) (counts \(pct)%)"
        }
        text += "\n\nAfter a week or so without alarms, the last few nights get close to your need. It's a clue that tends to run high, because catch-up sleep can last a while. The range shown is the range of the clues: how far apart they are. In the chart, the point where extra sleep stops improving the next day is another. How you feel counts least, because people who sleep too little for a while stop noticing it. The result is always kept between 6 and 10 hours."
        return text
    }

    // MARK: Accuracy

    private var accuracyCard: some View {
        let p = Palette(scheme: scheme)
        return Card {
            Text("Make it more accurate").font(.cardTitle)
            NavigationLink {
                CheckInView()
            } label: {
                HStack(spacing: 6) {
                    Text("Do the 10-second morning check-in").font(.bodyEmphasis)
                    Image(systemName: "chevron.right").font(.secondary).fontWeight(.bold).accessibilityHidden(true)
                }
                .foregroundStyle(Accent.mint.ink(scheme))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("How awake you feel each morning is a cross-check on the numbers from your Watch.")
                .font(.secondary)
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.purple.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(Accent.purple.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleep-need check on your next break").font(.bodyEmphasis)
                    Text("Sleep without an alarm for a week, like on a break. The last few nights get close to your need, though it's a clue that tends to run a little high while you catch up.")
                        .font(.secondary)
                        .foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Divider()
            LinkRow(title: "More ways to get accurate numbers", subtitle: "A checklist for your Watch and habits",
                    systemImage: "checklist", accent: .indigo) {
                AccuracyTipsView()
            }
        }
    }

    // MARK: Adjust

    private func adjust(by delta: Int) {
        store.data.sleepNeedAdjustment = min(max(store.data.sleepNeedAdjustment + delta, -60), 60)
    }

    private func adjustButton(systemImage: String, label: String, delta: Int, disabled: Bool) -> some View {
        let p = Palette(scheme: scheme)
        return Button {
            adjust(by: delta)
        } label: {
            Image(systemName: systemImage)
                .font(.cardTitle)
                .frame(width: 48, height: 48)
                .background(p.chip, in: Circle())
                .overlay(Circle().strokeBorder(p.cardBorder))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
    }

    private func adjustCard(_ need: SleepNeedEstimate) -> some View {
        let p = Palette(scheme: scheme)
        let adj = store.data.sleepNeedAdjustment
        let note = adj == 0
            ? "Adjust in 15-minute steps"
            : "Set to \(Clock.duration(need.minutes)) by you (\(SleepText.signed(Double(adj))) min)"
        return Card {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Think it's off?").font(.bodyEmphasis)
                    Text(note).font(.secondary).foregroundStyle(p.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                adjustButton(systemImage: "minus", label: "15 minutes less", delta: -15, disabled: adj <= -60)
                adjustButton(systemImage: "plus", label: "15 minutes more", delta: 15, disabled: adj >= 60)
            }
        }
    }
}

// MARK: - Pieces

/// A next-day measure to plot against hours slept.
private enum NeedMetric: String, CaseIterable, Identifiable {
    case hrv, restingHR, energy, felt
    var id: String { rawValue }

    var label: String {
        switch self {
        case .energy: return "Energy"
        case .hrv: return "HRV"
        case .restingHR: return "Rest HR"
        case .felt: return "Felt"
        }
    }

    var noun: String {
        switch self {
        case .energy: return "energy"
        case .hrv: return "HRV"
        case .restingHR: return "resting heart rate"
        case .felt: return "check-ins"
        }
    }

    var higherIsBetter: Bool { self != .restingHR }

    var accent: Accent {
        switch self {
        case .energy: return .mint
        case .hrv: return .indigo
        case .restingHR: return .pink
        case .felt: return .yellow
        }
    }

    /// Minimum padding above and below the data on the y axis.
    var minPad: Double {
        switch self {
        case .energy: return 2
        case .hrv: return 1
        case .restingHR: return 0.5
        case .felt: return 0.2
        }
    }

    var emptyDomain: ClosedRange<Double> {
        switch self {
        case .energy: return 40...80
        case .hrv: return -20...6
        case .restingHR: return -3...7
        case .felt: return 1...5
        }
    }

    func value(_ outcome: NextDayOutcome) -> Double? {
        switch self {
        case .energy: return outcome.energyScore
        case .hrv: return outcome.hrvDeltaPct
        case .restingHR: return outcome.restingHRDelta
        case .felt: return outcome.checkIn
        }
    }
}

private struct DosePoint: Identifiable {
    let id: Int
    let day: Date
    let hours: Double
    let value: Double
}

/// Scatter of nights with the fitted "helps until the knee" line.
private struct DoseResponseChart: View {
    let points: [DosePoint]
    let fit: KneeFit?
    let metric: NeedMetric
    let needRange: TimeRange
    let selected: DosePoint?
    @Binding var selection: Double?
    @Environment(\.colorScheme) private var scheme

    private var xDomain: ClosedRange<Double> {
        let hours = points.map(\.hours)
        let lo = min(5.0, (hours.min() ?? 5.0) - 0.25)
        let hi = max(9.5, (hours.max() ?? 9.5) + 0.25)
        return lo...hi
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return metric.emptyDomain }
        let pad = max((hi - lo) * 0.08, metric.minPad)
        return (lo - pad)...(hi + pad)
    }

    /// The fitted curve across the nights she actually has.
    private var fitLine: [DosePoint] {
        guard let fit, let lo = points.map(\.hours).min(), let hi = points.map(\.hours).max() else { return [] }
        let y = yDomain
        var out: [DosePoint] = []
        var h = lo
        var i = 0
        while h <= hi + 0.001 {
            let v = min(max(fit.value(atMinutes: h * 60), y.lowerBound), y.upperBound)
            out.append(DosePoint(id: i, day: .distantPast, hours: h, value: v))
            h += 0.125
            i += 1
        }
        return out
    }

    private var summary: String {
        var text = "\(metric.label) the next day against hours slept, \(points.count) nights."
        if let fit {
            text += " It improves with more sleep up to about \(Clock.duration(Int(fit.knee))), then levels off."
        }
        return text
    }

    @ChartContentBuilder
    private var bandMark: some ChartContent {
        RectangleMark(xStart: .value("Hours asleep", Double(needRange.start) / 60),
                      xEnd: .value("Hours asleep", Double(needRange.end) / 60),
                      yStart: .value(metric.label, yDomain.lowerBound),
                      yEnd: .value(metric.label, yDomain.upperBound))
            .foregroundStyle(Accent.purple.fill(scheme).opacity(0.14))
    }

    @ChartContentBuilder
    private var kneeMark: some ChartContent {
        if let fit {
            RuleMark(x: .value("Hours asleep", fit.knee / 60))
                .foregroundStyle(Palette(scheme: scheme).secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .center) {
                    Text(Clock.duration(Int(fit.knee)))
                        .font(.chartLabel(size: 11, weight: .bold))
                        .foregroundStyle(metric.accent.ink(scheme))
                }
        }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let selected {
            RuleMark(x: .value("Hours asleep", selected.hours))
                .foregroundStyle(Palette(scheme: scheme).primary.opacity(0.3))
            PointMark(x: .value("Hours asleep", selected.hours), y: .value(metric.label, selected.value))
                .foregroundStyle(metric.accent.ink(scheme))
                .symbolSize(110)
        }
    }

    var body: some View {
        // Light dots stay at 3:1 or more on white when nothing is picked
        // (Tanaka F7).
        let dotColor = metric.accent.fill(scheme).opacity(selected == nil ? (scheme == .dark ? 0.6 : 0.85) : 0.3)
        let lineColor = metric.accent.ink(scheme)
        Chart {
            bandMark
            ForEach(points) { pt in
                PointMark(x: .value("Hours asleep", pt.hours), y: .value(metric.label, pt.value))
                    .symbolSize(26)
                    .foregroundStyle(dotColor)
            }
            ForEach(fitLine) { pt in
                LineMark(x: .value("Hours asleep", pt.hours), y: .value(metric.label, pt.value))
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            kneeMark
            selectionMarks
        }
        .chartScrub($selection, snapped: selected?.hours, steps: Array(Set(points.map(\.hours))).sorted())
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: [5.0, 6.0, 7.0, 8.0, 9.0, 10.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let h = value.as(Double.self) {
                        Text("\(Int(h))h")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
        .accessibilityLabel(summary)
        .accessibilityChartDescriptor(ValueChartDescriptor(
            title: "\(metric.label) the next day against hours asleep", seriesName: "Nights",
            xTitle: "Hours asleep", yTitle: metric.label,
            points: points.map { ($0.hours, $0.value) },
            xLabel: { Clock.duration(Int(($0 * 60).rounded())) },
            yLabel: { String(format: "%.1f", $0) }))
    }
}

/// The need marker on a 6h-to-11h scale, with the adult 7–9h band.
private struct NeedRangeBar: View {
    var need: Int
    var range: TimeRange
    @Environment(\.colorScheme) private var scheme

    private func fraction(_ minutes: Int) -> CGFloat {
        CGFloat(min(max(Double(minutes - 360) / 300, 0), 1))
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track).frame(height: 8)
                    Capsule().fill(p.primary.opacity(0.16))
                        .frame(width: w * (fraction(540) - fraction(420)), height: 8)
                        .offset(x: w * fraction(420))
                    Capsule().fill(Accent.purple.fill(scheme))
                        .frame(width: max(8, w * (fraction(range.end) - fraction(range.start))), height: 16)
                        .offset(x: w * fraction(range.start))
                    RoundedRectangle(cornerRadius: 2).fill(p.primary)
                        .frame(width: 4, height: 26)
                        .offset(x: w * fraction(need) - 2)
                }
                .frame(width: w, height: 26)
            }
            .frame(height: 26)
            GeometryReader { geo in
                let w = geo.size.width
                ForEach([360, 420, 540, 660], id: \.self) { m in
                    Text("\(m / 60)h")
                        .font(.small).fontWeight(.semibold)
                        .foregroundStyle(p.tertiary)
                        .position(x: min(max(w * fraction(m), 10), w - 10), y: 8)
                }
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The range of the clues is \(Clock.duration(range.start)) to \(Clock.duration(range.end)). Most adults need between 7 and 9 hours.")
    }
}

/// One number in the "feeling fine" comparison.
private struct FeelStat: View {
    var title: String
    var value: String
    var note: String
    var accent: Accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.secondary).fontWeight(.semibold).foregroundStyle(p.secondary)
            Text(value).font(.numberM).minimumScaleFactor(0.7).lineLimit(1)
            Text(note).font(.secondary).fontWeight(.semibold).foregroundStyle(accent.ink(scheme))
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        .accessibilityElement(children: .ignore)
        // "3.4 of 5", not "3.4 slash 5" (Ortiz F8).
        .accessibilityLabel("\(title), \(value.replacingOccurrences(of: "/", with: " of ")), \(note)")
    }
}
