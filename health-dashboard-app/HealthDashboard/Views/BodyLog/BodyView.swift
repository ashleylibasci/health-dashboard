import SwiftUI
import HealthCore

/// The Body tab: a one-line summary (D-S4), where she is in her pack (or
/// cycle) and her energy, then one card of vitals led by the sick check,
/// then fitness and her body clock. Each row is a one-line answer that opens its screen; the
/// explanations live there. Recovery lives on Today, sleep on Sleep and
/// stress on Today, so nothing here repeats another tab.
struct BodyView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Screen(accent: .indigo, searches: true) {
            BodyLogTabHeader("Body")
            SampleDataBanner()
            summary
            rhythms
            vitals
            activity
        }
    }

    // MARK: Summary

    /// The 2-second answer, like every other tab (D-S4): what the sick
    /// check's signals say, then where she is in her pack and her energy.
    private var summary: some View {
        SummaryHeader(eyebrow: "Body today", value: signalsVerdict, line: summaryLine, accent: .indigo)
    }

    /// "Pill day 18 · 57% energy left now".
    private var summaryLine: String {
        let line = [rhythmPhrase, "\(Int(model.energyBankNow.rounded()))% energy left now"]
            .compactMap { $0 }.joined(separator: " \u{00B7} ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    /// The sick check's answer in a few words, the same order of trust as
    /// its row: what she logged, then whether there's a reading at all.
    private var signalsVerdict: String {
        if !model.loggedSickSymptoms.isEmpty { return "You feel sick" }
        guard model.hasHeartData else { return "No Watch reading" }
        let flagged = model.illness.factors.filter(\.flagged).count
        switch model.illness.confidence {
        case .none: return "Signals look usual"
        case .low: return flagged > 1 ? "\(flagged) signals moved a little" : "A signal moved a little"
        case .medium, .high: return "\(flagged) signals moved together"
        }
    }

    /// "pill day 18", "cycle day 12", "20 days since your period", or nil
    /// when there's no day to count.
    private var rhythmPhrase: String? {
        switch model.cycleDisplay {
        case let .pack(day, _, packLength):
            return store.birthControl == .combinedPill ? "pill day \(day)" : "day \(day) of \(packLength)"
        case let .phases(day, _, _), let .overdue(day, _):
            return "cycle day \(day)"
        case let .irregular(days?):
            return "\(days) day\(days == 1 ? "" : "s") since your period"
        case .irregular(nil), .suppressed, .notTracking:
            return nil
        }
    }

    // MARK: Rhythms: cycle and energy first

    private var cycleShown: Bool {
        if case .notTracking = model.cycleDisplay { return false }
        return true
    }

    @ViewBuilder
    private var rhythms: some View {
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
    }

    private var cycleLink: some View {
        NavigationLink { CycleView() } label: { cycleTile }
            .buttonStyle(.pressable)
    }

    private var energyLink: some View {
        NavigationLink { EnergyView() } label: {
            BodyTile(title: "Energy left", accent: .mint, systemImage: "bolt.fill",
                     value: "\(Int(model.energyBankNow.rounded()))%", progress: model.energyBankNow / 100,
                     note: model.lastNightIsFresh ? "About \(Int(model.energyBankAtBedtime.rounded()))% at bedtime"
                                                  : "No sleep recorded last night, so a rough guess")
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens your energy curve for today")
    }

    /// Cycle is pink in every state (Tanaka F4); coral is kept for "worse".
    /// On a pack it's named for the pack: "Pill pack · Day 18 of 28".
    @ViewBuilder
    private var cycleTile: some View {
        switch model.cycleDisplay {
        case let .phases(day, length, phase):
            BodyTile(title: "Cycle", accent: .pink, systemImage: "drop.fill",
                     value: day > length ? (model.showsDueAroundNow ? "Due around now" : "Day \(day)") : "Day \(day)",
                     progress: min(Double(day) / Double(max(length, 1)), 1),
                     note: day > length ? "Around \(model.usualLengthPhrase(length))"
                                        : "\(BodyLogStyle.phaseName(phase, birthControl: store.birthControl)) \u{00B7} \(periodNote)")
        case let .pack(day, activeDays, packLength):
            let hasBreak = activeDays < packLength
            let isBreak = hasBreak && day > activeDays
            let toBreak = activeDays - day + 1
            BodyTile(title: packTitle, accent: .pink, systemImage: "pills.fill",
                     value: "Day \(day) of \(packLength)", progress: Double(day) / Double(max(packLength, 1)),
                     note: !hasBreak ? "Continuous, no break"
                         : isBreak ? "\(model.packBreakName) \u{00B7} withdrawal bleed"
                         : model.packSkippingBreak ? "Skipping this break"
                         : "Break in \(toBreak) day\(toBreak == 1 ? "" : "s")")
        case let .suppressed(bc) where bc.hasBreakWeek:
            BodyTile(title: packTitle, accent: .pink, systemImage: "pills.fill",
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

    /// "Pill pack", "Ring", "Patch": what she'd call it (Dana, task 6).
    private var packTitle: String {
        switch store.birthControl {
        case .ring?: "Ring"
        case .patch?: "Patch"
        default: "Pill pack"
        }
    }

    private var periodNote: String {
        guard let days = model.periodCountdownDays else { return "no countdown" }
        return days <= 1 ? "period in about 1 day" : "period in about \(days) days"
    }

    // MARK: Vitals

    private var vitals: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading("Vitals")
            RowCard {
                sickRow
                RowDivider()
                HeartMetricRows()
            }
        }
    }

    /// The sick check's answer in one row. Breathing rate and wrist
    /// temperature are two of its four signals, so they live on its page.
    private var sickRow: some View {
        let ill = model.illness
        let flagged = ill.factors.filter(\.flagged).count
        let accent: Accent
        switch ill.confidence {
        case .none, .low: accent = .mint
        case .medium: accent = .orange
        case .high: accent = .coral
        }
        let feelsSick = !model.loggedSickSymptoms.isEmpty
        let verdict: RowVerdict
        let note: String
        if feelsSick {
            // What she logged beats what the Watch shows (round 4, Moreno F1).
            verdict = RowVerdict(text: "You feel sick", accent: .coral)
            note = "Trust how you feel"
        } else if !model.hasHeartData {
            verdict = RowVerdict(text: "No reading", accent: .indigo)
            note = "Wear your Watch to bed"
        } else {
            verdict = RowVerdict(text: ill.confidence.rawValue, accent: accent)
            switch ill.confidence {
            case .none: note = "Your signals look like your usual"
            case .low: note = "\(flagged == 0 ? "A signal" : "\(flagged) signal\(flagged == 1 ? "" : "s")") moved a little"
            case .medium, .high: note = "\(flagged) signals moved together"
            }
        }
        let calm = !feelsSick && (ill.confidence == .none || ill.confidence == .low)
        return MetricRow(title: "Sick check", note: note, verdict: verdict,
                         systemImage: calm ? "checkmark.shield.fill" : "thermometer.medium",
                         accent: feelsSick ? .coral : accent) {
            SickView()
        }
    }

    // MARK: Activity and body clock

    private var activity: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading("Fitness and body clock")
            RowCard {
                // "Fitness age", so it never reads as her own age (round 3).
                // Under eating-disorder history: VO₂ max as a plain number,
                // with no fitness age or ranking (round 3, H6).
                MetricRow(title: "Fitness",
                          note: fitnessNote,
                          value: model.vo2Max.map { String(format: "%.1f", $0) },
                          verdict: fitnessVerdict,
                          systemImage: "figure.run", accent: .mint) { FitnessView() }
                RowDivider()
                MetricRow(title: "Body clock", note: chronotypeNote,
                          systemImage: "sun.and.horizon.fill", accent: .purple) { ChronotypeView() }
                if model.showsCalories {
                    RowDivider()
                    MetricRow(title: "Calories", note: "kcal so far today", value: Int(model.caloriesToday.rounded()).formatted(),
                              systemImage: "bolt.heart.fill", accent: .orange) { CaloriesView() }
                }
            }
        }
    }

    private var fitnessNote: String {
        guard model.vo2Max != nil else { return "Needs a few outdoor walks" }
        if model.hidesActivityNumbers { return "VO\u{2082} max" }
        // With the verdict beside it there's room for the unit only; the
        // fitness age is one tap down (F29).
        if fitnessVerdict != nil { return "VO\u{2082} max \u{00B7} ml/kg/min" }
        return model.fitnessAgeText.map { "VO\u{2082} max \u{00B7} fitness age \($0.lowercased())" } ?? "VO\u{2082} max"
    }

    /// "Above average" / "About average" / "Below average" for women her
    /// age, the health team's bands (`fitnessLevel`), under the number (F29).
    /// None without her age, or with an eating-disorder history.
    private var fitnessVerdict: RowVerdict? {
        guard !model.hidesActivityNumbers, let level = model.fitnessLevel else { return nil }
        let band = level.components(separatedBy: " for ").first?.components(separatedBy: " compared").first ?? level
        let accent: Accent = band.hasPrefix("Above") ? .mint : band.hasPrefix("Below") ? .blue : .indigo
        return RowVerdict(text: band, accent: accent)
    }

    private var chronotypeNote: String {
        guard let type = model.chronotype else { return "Learning when your body prefers to sleep" }
        return type.category.rawValue
    }
}

/// Which way a value moved, and whether that needs attention: the arrow is
/// coral only when it does, mint when it's better than usual (Tanaka F2).
struct RowTrend {
    enum Tone { case worse, better, neutral }
    var up: Bool
    var tone: Tone
}

/// A Body tile on the neutral card surface: the icon and title in the
/// feature's colour, a one-line value, an optional progress bar (pack day,
/// energy left) and a short note.
private struct BodyTile: View {
    var title: String
    var accent: Accent
    var systemImage: String
    var value: String
    var progress: Double? = nil
    var note: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: systemImage)
                    .font(.scaled(size: 14, weight: .semibold))
                    .frame(width: Font.scaledSize(18))
                    .accessibilityHidden(true)
                Text(title).font(.bodyEmphasis)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(accent.ink(scheme))
            Text(value)
                .font(.cardTitle)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.track)
                        Capsule().fill(accent.fill(scheme))
                            .frame(width: max(6, geo.size.width * min(max(progress, 0), 1)))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
            Text(note).font(.secondary).secondaryText()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tileSurface()
        .contentShape(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, value, note].joined(separator: ", "))
    }
}
