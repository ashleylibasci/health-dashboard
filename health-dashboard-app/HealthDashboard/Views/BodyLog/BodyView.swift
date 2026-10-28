import SwiftUI
import Charts
import HealthCore

/// The Body tab. It leads with the two rhythms that change her day, cycle
/// and energy, then groups everything else into row cards: Vitals and
/// Progress. Recovery lives on Today, sleep stages on Sleep and stress on
/// Today, so nothing here repeats another tab (Whitfield F3/F4, Valtonen
/// F6). Explanations live on the screens each row opens (Valtonen F5).
struct BodyView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Screen(accent: .indigo) {
            BodyLogTabHeader("Body")
            SampleDataBanner()
            if model.showsCrisisLine { CrisisLineCard() }
            PackCheckCard()
            rhythms
            sickCard
            vitals
            progress
        }
    }

    // MARK: Rhythms: cycle and energy first

    private var cycleShown: Bool {
        if case .notTracking = model.cycleDisplay { return false }
        return true
    }

    private var rhythms: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading("Rhythms")
            if typeSize.isAccessibilitySize || !cycleShown {
                VStack(spacing: Space.m) {
                    if cycleShown { cycleLink }
                    energyLink
                }
            } else {
                Grid(horizontalSpacing: Space.m, verticalSpacing: Space.m) {
                    GridRow {
                        cycleLink
                        energyLink
                    }
                }
            }
            Card(density: .compact) {
                BodyRow(title: "Body clock", value: chronotypeValue, note: "When your body prefers to sleep",
                        systemImage: "sun.and.horizon.fill", accent: .purple) { ChronotypeView() }
            }
        }
    }

    private var cycleLink: some View {
        NavigationLink { CycleView() } label: { cycleTile }
            .buttonStyle(.pressable)
    }

    private var energyLink: some View {
        NavigationLink { EnergyView() } label: {
            BodyTile(title: "Energy left", accent: .mint, systemImage: "bolt.fill",
                     ring: model.energyBankNow / 100,
                     ringLabel: "\(Int(model.energyBankNow.rounded()))%", ringCaption: nil,
                     value: "Now",
                     note: model.lastNightIsFresh ? "About \(Int(model.energyBankAtBedtime.rounded()))% at bedtime"
                                                  : "No sleep recorded last night, so a rough guess")
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens your energy curve for today")
    }

    /// Cycle is pink in every state (Tanaka F4); coral is kept for "worse".
    @ViewBuilder
    private var cycleTile: some View {
        switch model.cycleDisplay {
        case let .phases(day, length, phase):
            BodyTile(title: "Cycle", accent: .pink, systemImage: "drop.fill",
                     ring: min(Double(day) / Double(max(length, 1)), 1), ringLabel: "\(day)", ringCaption: "Day",
                     value: day > length ? (model.showsDueAroundNow ? "Due around now" : "Day \(day)")
                                         : BodyLogStyle.phaseName(phase, birthControl: store.birthControl),
                     note: day > length ? "Around \(model.usualLengthPhrase(length))" : periodNote)
        case let .pack(day, activeDays, packLength):
            let hasBreak = activeDays < packLength
            let isBreak = hasBreak && day > activeDays
            let toBreak = activeDays - day + 1
            BodyTile(title: "Cycle", accent: .pink, systemImage: "pills.fill",
                     ring: Double(day) / Double(max(packLength, 1)), ringLabel: "\(day)", ringCaption: "Pack",
                     value: isBreak ? model.packBreakName : model.packActiveName,
                     note: !hasBreak ? "Continuous, no break"
                         : isBreak ? "Withdrawal bleed days"
                         : model.packSkippingBreak ? "Skipping this break"
                         : "Break in \(toBreak) day\(toBreak == 1 ? "" : "s")")
        case let .suppressed(bc) where bc.hasBreakWeek:
            BodyTile(title: "Cycle", accent: .pink, systemImage: "pills.fill",
                     value: bc.rawValue, note: "Set where you are in your pack")
        case let .suppressed(bc) where bc.ovulation != .stopped:
            BodyTile(title: "Cycle", accent: .pink, systemImage: "pills.fill",
                     value: bc.rawValue, note: "Long gaps between bleeds are common")
        case let .suppressed(bc):
            BodyTile(title: "Cycle", accent: .pink, systemImage: "pills.fill",
                     value: bc.rawValue, note: "No phases. Bleeding may vary")
        case let .overdue(day, typical):
            BodyTile(title: "Cycle", accent: .pink, systemImage: "drop.fill",
                     value: "Day \(day)", note: "Longer than \(model.usualLengthPhrase(typical))")
        case let .irregular(days):
            BodyTile(title: "Cycle", accent: .pink, systemImage: "drop.fill",
                     // The same count as Cycle and Log: days since the last period started (N11).
                     value: days.map { "\($0) day\($0 == 1 ? "" : "s")" } ?? "Log a period",
                     note: days == nil ? "No countdowns" : "Since your last period started")
        case .notTracking:
            EmptyView()
        }
    }

    private var periodNote: String {
        guard let days = model.periodCountdownDays else { return "No countdowns" }
        return days <= 1 ? "Period in about 1 day" : "Period in about \(days) days"
    }

    private var chronotypeValue: String {
        guard let type = model.chronotype else { return "Learning" }
        return type.category.rawValue.replacingOccurrences(of: " type", with: "")
    }

    // MARK: Might be getting sick

    private var sickCard: some View {
        let ill = model.illness
        let flagged = ill.factors.filter(\.flagged).count
        let accent: Accent
        switch ill.confidence {
        case .none, .low: accent = .mint
        case .medium: accent = .orange
        case .high: accent = .coral
        }
        let noData = !model.hasHeartData
        let title = noData ? "Sick check: no reading yet" : "Sick check: \(ill.confidence.rawValue.lowercased())"
        let note: String
        if !model.loggedSickSymptoms.isEmpty {
            // What she logged beats what the Watch shows (round 4, Moreno F1).
            note = "You logged feeling sick. Trust how you feel; tap to see when to get checked."
        } else if noData {
            note = "Needs your resting heart rate and HRV from last night. Wear your Watch to bed."
        } else {
            switch ill.confidence {
            case .none: note = "Heart rate, HRV, breathing and temperature look like your usual."
            case .low: note = "\(flagged == 0 ? "A signal" : "\(flagged) signal\(flagged == 1 ? "" : "s")") moved a little. Probably nothing; tap to see."
            case .medium, .high: note = "\(flagged) signals moved together. Tap to see what to do."
            }
        }
        let p = Palette(scheme: scheme)
        return NavigationLink { SickView() } label: {
            HStack(spacing: Space.m) {
                Image(systemName: ill.confidence == .none || ill.confidence == .low ? "checkmark.shield.fill" : "thermometer.medium")
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(accent.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).font(.bodyEmphasis)
                    Text(note).font(.secondary).foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(p.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tileSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .padding(.top, Space.s)
    }

    // MARK: Vitals

    private var vitals: some View {
        let heart = model.hasHeartData
        return VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading("Vitals")
            Card(density: .compact) {
                BodyRow(title: "HRV", value: heart ? "\(Int(model.hrv.rounded())) ms" : "No reading",
                        note: heart ? hrvNote : "Wear your Watch to bed", trend: heart ? hrvTrend : nil,
                        systemImage: "waveform.path.ecg", accent: .indigo) { HeartMetricView(metric: .hrv) }
                divider
                BodyRow(title: "Resting HR", value: heart ? "\(Int(model.restingHR.rounded())) bpm" : "No reading",
                        note: heart ? restingHRNote : "Wear your Watch to bed", trend: heart ? restingHRTrend : nil,
                        systemImage: "heart.fill", accent: .pink) { HeartMetricView(metric: .restingHR) }
                divider
                BodyRow(title: "Breathing", value: model.respiratoryRateDelta.map { signedDecimal($0, unit: "/min") } ?? "\u{2013}",
                        note: model.respiratoryRateDelta == nil ? "Wear your Watch to bed" : breathingNote,
                        systemImage: "lungs.fill", accent: .blue) { SickView() }
                    .accessibilityHint("Opens the sick check")
                divider
                BodyRow(title: "Wrist temp", value: model.wristTempDelta.map { TempFormat.delta($0) } ?? "\u{2013}",
                        note: model.wristTempDelta == nil ? "Wear your Watch to bed" : wristNote,
                        systemImage: "thermometer.medium", accent: .orange) { SickView() }
                    .accessibilityHint("Opens the sick check")
            }
        }
    }

    private var divider: some View {
        Divider().overlay(Palette(scheme: scheme).cardBorder).padding(.leading, Sizes.icon + Space.m)
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

    private func signedDecimal(_ value: Double, unit: String) -> String {
        let s = String(format: "%.1f", abs(value))
        return (value < -0.05 ? "\u{2212}" : "+") + s + unit
    }

    private var breathingNote: String {
        guard let d = model.respiratoryRateDelta else { return "" }
        return d >= 1 ? "Higher than usual" : "Compared with your usual"
    }

    private var wristNote: String {
        guard let d = model.wristTempDelta else { return "" }
        if model.inLutealPhase && d > 0 && d < 0.6 { return "Normal this phase" }
        return d >= 0.4 ? "Warmer than usual" : "Compared with your usual"
    }

    // MARK: Progress

    private var progress: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading("Progress")
            Card(density: .compact) {
                BodyRow(title: "Your week", value: model.weekRecap.map { "\($0.averageEnergy)" } ?? "Soon",
                        note: model.weekRecap == nil ? "Needs a week of nights" : "Average energy score, last week",
                        systemImage: "calendar", accent: .indigo) { WeekRecapView() }
                divider
                BodyRow(title: "Streaks", value: winsValue, note: winsNote,
                        systemImage: "flame.fill", accent: .orange) { AchievementsView() }
                divider
                BodyRow(title: "Fitness",
                        // "Fitness age", so it never reads as her own age (round 3).
                        // Under eating-disorder history: VO₂ max as a plain number,
                        // with no fitness age or ranking (round 3, H6).
                        value: model.hidesActivityNumbers
                            ? (model.vo2Max.map { String(format: "%.1f", $0) } ?? "\u{2013}")
                            : (model.fitnessAgeText.map { "Fitness age \($0.lowercased())" } ?? "\u{2013}"),
                        note: model.vo2Max.map { v in
                            let value = "VO\u{2082} max \(String(format: "%.1f", v))"
                            return model.hidesActivityNumbers ? "VO\u{2082} max" : "\(value) \u{00B7} \(model.fitnessLevelShown ?? "")"
                        } ?? "Needs a few outdoor walks",
                        systemImage: "figure.run", accent: .mint) { FitnessView() }
                if model.showsCalories {
                    divider
                    BodyRow(title: "Calories", value: Int(model.caloriesToday.rounded()).formatted(), note: "kcal so far today",
                            systemImage: "bolt.heart.fill", accent: .orange) { CaloriesView() }
                }
            }
        }
    }

    private var winsValue: String {
        let best = model.streaks.max { $0.current < $1.current }
        return best.map { "\($0.current)" } ?? "0"
    }

    private var winsNote: String {
        guard let best = model.streaks.max(by: { $0.current < $1.current }), best.current > 0 else { return "Start one tonight" }
        return "\(best.unit.capitalized): \(best.title.lowercased())"
    }
}

/// A row in a Body card: icon tile, title and note, the value on the right
/// and a chevron. At accessibility sizes the value goes under the title.
struct BodyRow<Destination: View>: View {

    var title: String
    var value: String
    var note: String
    var trend: RowTrend? = nil
    var systemImage: String
    var accent: Accent
    @ViewBuilder var destination: Destination
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let p = Palette(scheme: scheme)
        NavigationLink { destination } label: {
            HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: Space.m) {
                Image(systemName: systemImage)
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(accent.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .accessibilityHidden(true)
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(title).font(.bodyEmphasis)
                        valueText
                        noteLine(p)
                    }
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(title).font(.bodyEmphasis)
                        noteLine(p)
                    }
                    Spacer(minLength: Space.s)
                    valueText
                        .multilineTextAlignment(.trailing)
                }
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(p.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Sizes.tallRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value), \(note)")
        .accessibilityAddTraits(.isButton)
    }

    private var valueText: some View {
        Text(value)
            .font(.cardTitle)
            .monospacedDigit()
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func noteLine(_ p: Palette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let trend {
                Image(systemName: trend.up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.scaled(size: 8, weight: .bold))
                    .foregroundStyle(trendColor(trend.tone, p))
                    .accessibilityHidden(true)
            }
            Text(note).font(.secondary).foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func trendColor(_ tone: RowTrend.Tone, _ p: Palette) -> Color {
        switch tone {
        case .worse: Accent.coral.ink(scheme)
        case .better: Accent.mint.ink(scheme)
        case .neutral: p.tertiary
        }
    }
}

/// Which way a value moved, and whether that needs attention: the arrow is
/// coral only when it does, mint when it's better than usual (Tanaka F2).
struct RowTrend {
    enum Tone { case worse, better, neutral }
    var up: Bool
    var tone: Tone
}

/// A Body tile on the neutral card surface, the icon and title in the
/// feature's colour. With `ring` set it shows a small ring next to the
/// value.
private struct BodyTile: View {
    var title: String
    var accent: Accent
    var systemImage: String
    var ring: Double? = nil
    var ringLabel: String = ""
    var ringCaption: String? = nil
    var value: String
    var note: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: systemImage)
                    .font(.scaled(size: 14, weight: .semibold))
                    .frame(width: Font.scaledSize(18))
                    .accessibilityHidden(true)
                Text(title).font(.bodyEmphasis)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(accent.ink(scheme))
            if let ring {
                HStack(spacing: Space.m) {
                    Ring(value: ring, accent: accent, lineWidth: 7, label: ringLabel, caption: ringCaption, size: 68)
                    Text(value)
                        .font(.scaledNumber(18))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Text(value)
                    .font(.numberM)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            if !note.isEmpty {
                Text(note).font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tileSurface()
        .contentShape(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [title]
        if ring != nil {
            parts.append(ringCaption.map { "\($0) \(ringLabel)" } ?? ringLabel)
        }
        parts.append(value)
        if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Trend

/// HRV, resting heart rate or sleep over the last 14 nights. Drag across it
/// to read any night against your usual.
private struct BodyTrendCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var metric: Metric
    @State private var selected: Date? = nil

    init(metric: Metric = .hrv) {
        _metric = State(wrappedValue: metric)
    }

    enum Metric: String, CaseIterable, Hashable {
        case hrv = "HRV", restingHR = "Resting HR", sleep = "Sleep"
    }

    private struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    private var points: [Point] {
        model.bodyTrend.compactMap { t in
            switch metric {
            case .hrv: return t.hrv.map { Point(date: t.date, value: $0) }
            case .restingHR: return t.restingHR.map { Point(date: t.date, value: $0) }
            case .sleep: return Point(date: t.date, value: Double(t.asleep) / 60)
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

    private var shown: Point? {
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
            case .above, .wellBelow: return "\(Int(d.rounded())) beats above your usual: often short sleep, stress, drinks or a bug coming on\(model.heartCycleCause)."
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

    var body: some View {
        Card {
            HStack {
                ExplainedTitle(text: "Last 14 nights", explanation: explanation, size: 17)
                Spacer()
            }
            AdaptiveSegmentedPicker("Measure", selection: $metric, options: Array(Metric.allCases)) { m in m.rawValue }
            if let p = shown {
                ChartReadout(title: selected == nil ? "Last night \u{00B7} \(p.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
                                                    : p.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                             value: format(p.value), detail: meaning(p.value), accent: accent)
            }
            if points.count >= 2 {
                chart
                ScrubHint()
            } else {
                Text("Not enough nights yet.").font(.scaled(size: 14)).secondaryText()
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let vs = points.map(\.value) + [usual]
        let lo = vs.min() ?? 0, hi = vs.max() ?? 1
        let pad = max((hi - lo) * 0.2, metric == .sleep ? 0.5 : 2)
        return (lo - pad)...(hi + pad)
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("Usual", usual))
                .foregroundStyle(Palette(scheme: scheme).tertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text(metric == .sleep ? "Your need" : "Your usual").font(.chartLabel(size: 10, weight: .semibold)).secondaryText()
                }
            ForEach(points) { p in
                LineMark(x: .value("Night", p.date), y: .value(metric.rawValue, p.value))
                    .foregroundStyle(accent.fill(scheme))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            if let p = shown {
                RuleMark(x: .value("Night", p.date))
                    .foregroundStyle(Palette(scheme: scheme).tertiary)
                PointMark(x: .value("Night", p.date), y: .value(metric.rawValue, p.value))
                    .foregroundStyle(accent.ink(scheme))
                    .symbolSize(80)
            }
        }
        .chartYScale(domain: yDomain)
        .chartScrub($selected, snapped: selected == nil ? nil : shown?.date, steps: points.map(\.date))
        .frame(height: 160)
        .accessibilityLabel("\(metric.rawValue) over the last 14 nights. Latest \(points.last.map { format($0.value) } ?? "none").")
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
            case .above, .wellBelow: return "\(v) beats above your usual. Often short sleep, stress, drinks or a bug coming on\(model.heartCycleCause)."
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
                    if model.hasHeartData && !model.heartIsReal { ExampleTag() }
                }
                Text(value).font(.scaledNumber(36))
                Text(change).font(.scaled(size: 15)).fixedSize(horizontal: false, vertical: true)
                if model.hasHeartData && metric == .hrv && model.hrvIsOvernight {
                    Text("From readings taken while you slept.").font(.scaled(size: 13)).secondaryText()
                }
            }
            BodyTrendCard(metric: metric == .hrv ? .hrv : .restingHR)
            Card {
                LinkRow(title: "Recovery", subtitle: "How this and your other numbers add up today",
                        systemImage: "heart.fill", accent: .indigo) {
                    RecoveryView()
                }
            }
            HowWeGotThisLink(explanation: explanation)
        }
    }
}

