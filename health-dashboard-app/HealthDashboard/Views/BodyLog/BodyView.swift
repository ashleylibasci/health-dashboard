import SwiftUI
import Charts
import HealthCore

/// The Body tab: recovery up top, a scrubbable 14-night trend, then a grid of
/// tiles into each detail screen. Every tile has an ⓘ.
struct BodyView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Tile: Hashable {
        case cycle, energy, stress, hrv, restingHR, breathing, wristTemp, fitness, calories, sleepStages, chronotype, weekRecap, wins
    }

    var body: some View {
        Screen(accent: .indigo) {
            BodyLogTabHeader("Body")
            SampleDataBanner()
            if model.showsCrisisLine { CrisisLineCard() }
            PackCheckCard()
            recoveryHero
            HowWeGotThisLink(topic: .recovery)
            sickCard
            tileGrid
            BodyTrendCard()
            conditionsRow
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Image(systemName: "gearshape")
                        .font(.scaled(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    // MARK: Recovery

    private var recoveryHero: some View {
        let p = Palette(scheme: scheme)
        return ZStack(alignment: .topTrailing) {
            NavigationLink { RecoveryView() } label: {
                AdaptiveStack(spacing: 16) {
                    Ring(value: Double(model.recoveryShown ?? 0) / 100, accent: .indigo, lineWidth: 12,
                         label: model.recoveryShown.map { "\($0)" } ?? "\u{2013}", caption: "Recovery", size: 112)
                    VStack(alignment: .leading, spacing: 6) {
                        FlowLayout(spacing: 6) {
                            Text(model.recoveryShown == nil ? "No reading yet" : model.recoveryLabel)
                                .font(.scaled(size: 20, weight: .bold))
                            if model.recoveryIsExample { ExampleTag() }
                        }
                        Text(model.recoveryUsualNote)
                            .font(.scaled(size: 14)).secondaryText()
                        if model.hasHeartData {
                            FlowLayout(spacing: 6) {
                                deltaPill(label: "HRV \(Int(model.hrv.rounded()))", delta: percentText(model.hrvDeltaPct), accent: .coral)
                                deltaPill(label: "RHR \(Int(model.restingHR.rounded()))", delta: signedText(model.restingHRDelta), accent: .pink)
                            }
                        } else {
                            Text("HRV and resting HR: no reading yet").font(.scaled(size: 12, weight: .semibold)).secondaryText()
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 13, weight: .bold))
                        .foregroundStyle(p.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(p.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(p.cardBorder))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recoveryAccessibility)
            .accessibilityAddTraits(.isButton)
            InfoButton(topic: .recovery).padding(2)
        }
    }

    private var recoveryAccessibility: String {
        var text: String
        if let score = model.recoveryShown {
            text = "Recovery \(score), \(model.recoveryLabel)\(model.recoveryIsExample ? ", example" : ""). \(model.recoveryUsualNote)"
        } else {
            text = "Recovery: no reading yet."
        }
        if model.hasHeartData {
            text += " HRV \(Int(model.hrv.rounded())), \(percentText(model.hrvDeltaPct)). Resting heart rate \(Int(model.restingHR.rounded())), \(signedText(model.restingHRDelta))."
        } else {
            text += " No HRV or resting heart rate reading yet."
        }
        return text
    }

    private func deltaPill(label: String, delta: String, accent: Accent) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text(delta).foregroundStyle(accent.ink(scheme))
        }
        .keepsOnOneLine(minimumScale: 0.7)
        .font(.scaled(size: 12, weight: .semibold))
        .padding(.horizontal, 9)
        .frame(minHeight: Font.scaledSize(24))
        .background(accent.fill(scheme).opacity(0.18), in: Capsule())
    }

    private func percentText(_ value: Double) -> String {
        let v = Int(value.rounded())
        return v < 0 ? "\u{2212}\(abs(v))%" : "+\(v)%"
    }

    private func signedText(_ value: Double) -> String {
        let v = Int(value.rounded())
        return v < 0 ? "\u{2212}\(abs(v))" : "+\(v)"
    }

    private func signedDecimal(_ value: Double, unit: String) -> String {
        let s = String(format: "%.1f", abs(value))
        return (value < -0.05 ? "\u{2212}" : "+") + s + unit
    }

    // MARK: Might be getting sick

    private var sickCard: some View {
        let ill = model.illness
        let flagged = ill.factors.filter(\.flagged).count
        let accent: Accent
        switch ill.confidence {
        case .none, .low: accent = .mint
        case .medium: accent = .orange
        case .high: accent = .pink
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
        return ZStack(alignment: .topTrailing) {
            NavigationLink { SickView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: ill.confidence == .none || ill.confidence == .low ? "checkmark.shield.fill" : "thermometer.medium")
                        .font(.scaled(size: 17, weight: .semibold))
                        .foregroundStyle(accent.ink(scheme))
                        .frame(width: 40, height: 40)
                        .background(accent.fill(scheme).opacity(0.22), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.scaled(size: 15, weight: .bold))
                        Text(note).font(.scaled(size: 13)).secondaryText().fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 30)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(accent.fill(scheme).opacity(0.2)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            InfoButton(topic: .illness)
        }
    }

    // MARK: Tiles

    private var tiles: [Tile] {
        var list: [Tile] = []
        if cycleTileShown { list.append(.cycle) }
        list.append(contentsOf: [.energy, .stress, .hrv, .restingHR, .breathing, .wristTemp, .fitness])
        if model.showsCalories { list.append(.calories) }
        list.append(contentsOf: [.sleepStages, .chronotype, .weekRecap, .wins])
        return list
    }

    private var cycleTileShown: Bool {
        if case .notTracking = model.cycleDisplay { return false }
        return true
    }

    /// Two tiles a row, or one at accessibility text sizes so titles
    /// aren't cut to "Rest…".
    private var tileRows: [[Tile]] {
        let list = tiles
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        return stride(from: 0, to: list.count, by: perRow).map { Array(list[$0..<min($0 + perRow, list.count)]) }
    }

    private var tileGrid: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(tileRows, id: \.self) { row in
                GridRow {
                    if row.count == 2 {
                        tileLink(row[0])
                        tileLink(row[1])
                    } else if let only = row.first {
                        tileLink(only).gridCellColumns(typeSize.isAccessibilitySize ? 1 : 2)
                    }
                }
            }
        }
    }

    private func tileLink(_ tile: Tile) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink { destination(tile) } label: { tileView(tile) }
                .buttonStyle(.plain)
                .accessibilityHint(tile == .breathing || tile == .wristTemp ? "Opens the sick check" : "")
            InfoButton(explanation: info(tile))
        }
    }

    @ViewBuilder
    private func destination(_ tile: Tile) -> some View {
        switch tile {
        case .cycle: CycleView()
        case .energy: EnergyView()
        case .stress: StressView()
        case .hrv: HeartMetricView(metric: .hrv)
        case .restingHR: HeartMetricView(metric: .restingHR)
        case .breathing, .wristTemp: SickView()
        case .fitness: FitnessView()
        case .calories: CaloriesView()
        case .sleepStages: SleepStagesView()
        case .chronotype: ChronotypeView()
        case .weekRecap: WeekRecapView()
        case .wins: AchievementsView()
        }
    }

    private func info(_ tile: Tile) -> Explanation {
        switch tile {
        case .cycle: return cycleInfo
        case .energy: return Topic.energyBank.explanation
        case .stress: return Topic.stress.explanation
        case .hrv: return model.hrvExplanation
        case .restingHR: return model.restingHRExplanation
        case .breathing: return Topic.breathingRate.explanation
        case .wristTemp: return BodyLogStyle.wristTempExplanation(ovulationStopped: model.ovulationStopped)
        case .fitness: return Topic.fitnessAge.explanation
        case .calories: return Topic.calories.explanation
        case .sleepStages: return Topic.sleepStages.explanation
        case .chronotype: return Topic.bodyClock.explanation
        case .weekRecap: return Topic.energyScore.explanation
        case .wins: return Explanation(id: "wins", title: "Wins",
                                       meaning: "Streaks and milestones from your own habits: in bed on time, meeting your sleep need, morning check-ins.",
                                       forYou: "Small streaks add up. Missing a night just starts a new one; it never erases what you did.")
        }
    }

    private var cycleInfo: Explanation {
        switch model.cycleDisplay {
        case let .phases(_, _, phase):
            switch phase {
            case .period: return Topic.period.explanation
            case .follicular: return Topic.follicular.explanation
            case .ovulation: return Topic.ovulation.explanation
            case .luteal, .unknown: return Topic.luteal.explanation
            }
        case .pack: return Topic.pillPack.explanation
        case let .suppressed(bc) where bc.hasBreakWeek:
            return Explanation(id: "packUnknown", title: bc.rawValue, meaning: bc.note,
                               forYou: "Set where you are in your pack (Cycle or Settings) so the app can show your active days and break week.")
        case let .suppressed(bc) where bc.ovulation != .stopped:
            return Explanation(id: "longGap", title: bc.rawValue, meaning: bc.note,
                               forYou: "A long gap between bleeds is common on your method, so the app doesn't count down or call it late. Log any bleeding to keep a history. \(CycleCare.bleedingRedFlags)")
        case let .suppressed(bc):
            return Explanation(id: "suppressed", title: bc.rawValue,
                               meaning: bc.note,
                               forYou: "There are no cycle phases or period countdowns on your method. Bleeding may be light, irregular or absent, and that's expected. \(CycleCare.bleedingRedFlags)")
        case let .overdue(day, typical):
            return Explanation(id: "overdue", title: "Longer cycle",
                               meaning: "Cycles vary. One that runs past your usual length now and then is common, and stress, illness or travel can delay a period.",
                               forYou: "You're on day \(day), longer than \(model.usualLengthPhrase(typical)). Log your period when it starts. If you could be pregnant, or this keeps happening, check with a doctor. \(CycleCare.redS)")
        case .irregular:
            return Explanation(id: "irregular", title: "Irregular cycle",
                               meaning: model.irregularReasonText ?? "Your cycles vary a lot in length, so the app counts days since your last period instead of predicting the next one.",
                               forYou: "Log the first day of each period. The history of your cycle lengths is useful to show a doctor.\(model.cycleIsNatural ? " " + CycleCare.redS : "")")
        case .notTracking: return Topic.period.explanation
        }
    }

    @ViewBuilder
    private func tileView(_ tile: Tile) -> some View {
        switch tile {
        case .cycle: cycleTile
        case .energy:
            BodyTile(title: "Energy left", accent: .yellow, systemImage: "bolt.fill",
                     ring: model.energyBankNow / 100,
                     ringLabel: "\(Int(model.energyBankNow.rounded()))%", ringCaption: nil,
                     value: "Now",
                     note: model.lastNightIsFresh ? "~\(Int(model.energyBankAtBedtime.rounded()))% at bedtime"
                                                  : "No sleep recorded last night, so a rough guess")
        case .stress:
            BodyTile(title: "Stress", accent: .orange, systemImage: "waveform.path",
                     value: stressValue, note: stressNote)
        case .hrv:
            BodyTile(title: "HRV", accent: .coral, systemImage: "waveform.path.ecg",
                     value: model.hasHeartData ? "\(Int(model.hrv.rounded())) ms" : "No reading yet",
                     note: model.hasHeartData ? "\(percentText(model.hrvDeltaPct)) vs your usual" : "Wear your Watch to bed")
        case .restingHR:
            BodyTile(title: "Resting HR", accent: .pink, systemImage: "heart.fill",
                     value: model.hasHeartData ? "\(Int(model.restingHR.rounded())) bpm" : "No reading yet",
                     note: model.hasHeartData ? "\(signedText(model.restingHRDelta)) vs your usual" : "Wear your Watch to bed")
        case .breathing:
            BodyTile(title: "Breathing", accent: .blue, systemImage: "lungs.fill",
                     value: model.respiratoryRateDelta.map { signedDecimal($0, unit: "/min") } ?? "\u{2013}",
                     note: model.respiratoryRateDelta == nil ? "Wear your Watch to bed" : breathingNote)
        case .wristTemp:
            BodyTile(title: "Wrist temp", accent: .coral, systemImage: "thermometer.medium",
                     value: model.wristTempDelta.map { TempFormat.delta($0) } ?? "\u{2013}",
                     note: model.wristTempDelta == nil ? "Wear your Watch to bed" : wristNote)
        case .fitness:
            BodyTile(title: "Fitness", accent: .mint, systemImage: "figure.run",
                     // "Fitness age", so it never reads as her own age (round 3).
                     // Under eating-disorder history: VO₂ max as a plain number,
                     // with no fitness age or ranking (round 3, H6).
                     value: model.hidesActivityNumbers
                        ? (model.vo2Max.map { String(format: "%.1f", $0) } ?? "\u{2013}")
                        : (model.fitnessAgeText.map { "Fitness age \($0.lowercased())" } ?? "\u{2013}"),
                     note: model.vo2Max.map { v in
                         let value = "VO\u{2082} max \(String(format: "%.1f", v))"
                         return model.hidesActivityNumbers ? "VO\u{2082} max" : "\(value) \u{00B7} \(model.fitnessLevelShown ?? "")"
                     } ?? "Needs a few outdoor walks")
        case .calories:
            BodyTile(title: "Calories", accent: .orange, systemImage: "flame.fill",
                     value: Int(model.caloriesToday.rounded()).formatted(), note: "kcal so far")
        case .sleepStages:
            BodyTile(title: "Sleep stages", accent: .purple, systemImage: "moon.stars.fill",
                     value: model.lastNightIsFresh ? Clock.duration(model.lastNight.asleep) : "No sleep",
                     note: model.lastNightIsFresh ? "Last night" : "None recorded last night")
        case .chronotype:
            BodyTile(title: "Body clock", accent: .blue, systemImage: "sun.and.horizon.fill",
                     value: chronotypeValue, note: "When your body prefers to sleep")
        case .weekRecap:
            BodyTile(title: "Last week", accent: .indigo, systemImage: "calendar",
                     value: model.weekRecap.map { "\($0.averageEnergy)" } ?? "Soon",
                     note: model.weekRecap == nil ? "Needs a week of nights" : "Average energy score")
        case .wins:
            BodyTile(title: "Wins", accent: .yellow, systemImage: "trophy.fill",
                     value: winsValue, note: winsNote)
        }
    }

    @ViewBuilder
    private var cycleTile: some View {
        switch model.cycleDisplay {
        case let .phases(day, length, phase):
            BodyTile(title: "Cycle", accent: day > length ? .indigo : BodyLogStyle.phaseAccent(phase), systemImage: "drop.fill",
                     ring: min(Double(day) / Double(max(length, 1)), 1), ringLabel: "\(day)", ringCaption: "Day",
                     value: day > length ? (model.showsDueAroundNow ? "Due around now" : "Day \(day)")
                                         : BodyLogStyle.phaseName(phase, birthControl: store.birthControl),
                     note: day > length ? "Around \(model.usualLengthPhrase(length))" : periodNote)
        case let .pack(day, activeDays, packLength):
            let hasBreak = activeDays < packLength
            let isBreak = hasBreak && day > activeDays
            let toBreak = activeDays - day + 1
            BodyTile(title: "Cycle", accent: isBreak ? .coral : .indigo, systemImage: "pills.fill",
                     ring: Double(day) / Double(max(packLength, 1)), ringLabel: "\(day)", ringCaption: "Pack",
                     value: isBreak ? model.packBreakName : model.packActiveName,
                     note: !hasBreak ? "Continuous, no break"
                         : isBreak ? "Withdrawal bleed days"
                         : model.packSkippingBreak ? "Skipping this break"
                         : "Break in \(toBreak) day\(toBreak == 1 ? "" : "s")")
        case let .suppressed(bc) where bc.hasBreakWeek:
            BodyTile(title: "Cycle", accent: .indigo, systemImage: "pills.fill",
                     value: bc.rawValue, note: "Set where you are in your pack")
        case let .suppressed(bc) where bc.ovulation != .stopped:
            BodyTile(title: "Cycle", accent: .indigo, systemImage: "pills.fill",
                     value: bc.rawValue, note: "Long gaps between bleeds are common")
        case let .suppressed(bc):
            BodyTile(title: "Cycle", accent: .indigo, systemImage: "pills.fill",
                     value: bc.rawValue, note: "No phases. Bleeding may vary")
        case let .overdue(day, typical):
            BodyTile(title: "Cycle", accent: .indigo, systemImage: "drop.fill",
                     value: "Day \(day)", note: "Longer than \(model.usualLengthPhrase(typical))")
        case let .irregular(days):
            BodyTile(title: "Cycle", accent: .coral, systemImage: "drop.fill",
                     // The same count as Cycle and Log: days since the last period started (N11).
                     value: days.map { "\($0) day\($0 == 1 ? "" : "s")" } ?? "Log a period",
                     note: days == nil ? "No countdowns" : "Since your last period started")
        case .notTracking:
            EmptyView()
        }
    }

    private var periodNote: String {
        guard let days = model.periodCountdownDays else { return "No countdowns" }
        return days <= 1 ? "Period in ~1 day" : "Period in ~\(days) days"
    }

    /// The same wording as the Today tab.
    private var stressValue: String {
        if let felt = model.stressLoggedToday { return "Felt \(felt)/5" }
        if let label = model.stressToday.label { return label.rawValue }
        return "No data yet"
    }

    private var stressNote: String {
        if let label = model.stressToday.label {
            return model.stressLoggedToday != nil ? "Body signals: \(label.rawValue.lowercased())" : "Body signals at rest"
        }
        if model.stressLoggedToday != nil { return "What you logged today" }
        return model.restingHRBaselineKnown ? "Wear your Watch today" : "Learning your resting heart rate"
    }

    private var breathingNote: String {
        guard let d = model.respiratoryRateDelta else { return "" }
        return d >= 1 ? "Higher than usual" : "vs usual \u{00B7} sick check"
    }

    private var wristNote: String {
        guard let d = model.wristTempDelta else { return "" }
        if model.inLutealPhase && d > 0 && d < 0.6 { return "Normal this phase" }
        return d >= 0.4 ? "Warmer than usual" : "vs your usual \u{00B7} sick check"
    }

    private var winsValue: String {
        let best = model.streaks.max { $0.current < $1.current }
        return best.map { "\($0.current)" } ?? "0"
    }

    private var winsNote: String {
        guard let best = model.streaks.max(by: { $0.current < $1.current }) else { return "Streaks" }
        return "\(best.unit.capitalized): \(best.title.lowercased())"
    }

    private var chronotypeValue: String {
        guard let type = model.chronotype else { return "Learning" }
        return type.category.rawValue.replacingOccurrences(of: " type", with: "")
    }

    // MARK: Conditions

    private var conditionsRow: some View {
        Card {
            LinkRow(title: "Health conditions",
                    subtitle: store.data.conditions.isEmpty
                        ? "Optional. Private, stays on your phone"
                        : store.data.conditions.joined(separator: ", "),
                    systemImage: "heart.text.square.fill", accent: .purple) {
                ConditionsView()
            }
        }
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
        case .hrv: .coral
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
    private var accent: Accent { metric == .hrv ? .coral : .pink }

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

/// A tinted tile. With `ring` set it shows a small ring next to the value.
/// The top-right corner is left free for the ⓘ button.
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
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(accent.ink(scheme))
                    .accessibilityHidden(true)
                Text(title).font(.scaled(size: 14, weight: .bold))
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 30)
            }
            .frame(minHeight: 20)
            if let ring {
                HStack(spacing: 10) {
                    Ring(value: ring, accent: accent, lineWidth: 7, label: ringLabel, caption: ringCaption, size: 67)
                    Text(value)
                        .font(.scaledNumber(18))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Text(value)
                    .font(.scaledNumber(22))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            if !note.isEmpty {
                Text(note).font(.scaled(size: 12, weight: .semibold)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(accent.tint(scheme), in: shape)
        .overlay(shape.strokeBorder(accent.fill(scheme).opacity(0.18)))
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
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
