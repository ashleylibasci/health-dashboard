import SwiftUI
import HealthCore

/// "How your cycle affects you": each phase's usual effect on energy,
/// sleep, HRV, resting heart rate, mood and exercise. On a method that stops
/// ovulation it explains pack weeks (or steady hormones) instead of phases.
struct CyclePhasesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // One title, the nav title, named like the link that opens it
        // (Valtonen F8). Pill, ring and patch: her month is a pack, not a cycle.
        Screen(title: model.usesPackWording ? "How your pack affects you" : "How your cycle affects you", accent: .pink) {
            SampleDataBanner()

            content
            termsCard

            Text("Patterns, not medical advice. If something feels off, talk to a doctor.")
                .font(.secondary)
                .secondaryText()
            HowWeGotThisLink(title: "Cycle patterns",
                             method: "The typical effects come from studies of heart rate, HRV, temperature and sleep across the menstrual cycle. When you have at least two cycles of Apple Watch nights, we line each night up with its cycle day and compare your sleep, HRV and resting heart rate in each phase with your overall average.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.ovulationStopped, let bc = store.birthControl {
            methodContent(bc)
        } else {
            switch model.cycleDisplay {
            case let .phases(day, length, _):
                phasesContent(day: day, length: length)
            case .irregular:
                intro("Your cycles vary, so phases don't land on the same days each month. These are the usual effects of each phase whenever it comes.")
                if let d = model.daysSinceLastPeriodStart {
                    Text(d == 0 ? "Your period started today." : "\(d) day\(d == 1 ? "" : "s") since your last period started.")
                        .font(.bodyEmphasis).secondaryText()
                }
                phaseCards(length: nil, today: nil)
            case let .overdue(day, typical):
                intro("You're on day \(day), longer than your usual ~\(typical) days, so the app doesn't place you in a phase until your next period starts. These are the usual effects of each phase.")
                phaseCards(length: nil, today: nil)
            default:
                intro("You're not tracking a cycle right now. Here's how a natural cycle usually affects the body, in case it's useful.")
                phaseCards(length: nil, today: nil)
            }
        }
    }

    private func intro(_ text: String) -> some View {
        Text(text).font(.bodyText).secondaryText().fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Natural phases

    @ViewBuilder
    private func phasesContent(day: Int, length: Int) -> some View {
        // Okafor I: many women notice no difference between phases.
        if let avg = model.phaseAverages, !avg.isEmpty {
            intro("Your own averages from \(model.nights.count) nights of Apple Watch data, compared with your normal, plus what some people notice in each phase. Many women notice no difference. Go by your own pattern.")
        } else {
            intro("Many women notice no difference between phases. Some feel flatter before or during their period. Go by your own pattern; your averages appear here after two cycles of Apple Watch nights.")
        }
        if store.birthControl == .miniPill {
            Card(accent: .yellow) {
                Text("On the mini pill some people release an egg each cycle and some don't, so these phases are a rough guide for you.")
                    .font(.bodyText).fixedSize(horizontal: false, vertical: true)
            }
        }
        Card {
            CycleStrip(length: length, today: min(day, length),
                       color: { d in BodyLogStyle.phaseFill(model.cyclePhase(day: d, length: length), scheme) },
                       readout: { d in CycleCopy.dayReadout(day: d, length: length, birthControl: store.birthControl, isToday: d == day, periodLength: model.periodLength) },
                       letter: { d in BodyLogStyle.phaseLetter(model.cyclePhase(day: d, length: length), birthControl: store.birthControl) })
        }
        phaseCards(length: length, today: day)
        if CycleEstimator.isLateLuteal(day: day, length: length) {
            HStack(spacing: 8) {
                tipPill("Bed by \(Clock.format(store.data.bedtime))", systemImage: "moon.fill", accent: .purple)
                tipPill(model.caffeineCutoffShown.map { "Caffeine cutoff \(BodyLogStyle.shortTime($0))" } ?? "Caffeine: one small drink early", systemImage: "cup.and.saucer.fill", accent: .yellow)
            }
        }
    }

    private func tipPill(_ text: String, systemImage: String, accent: Accent) -> some View {
        Label(text, systemImage: systemImage)
            .font(.secondary).fontWeight(.semibold)
            .foregroundStyle(accent.ink(scheme))
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(accent.tint(scheme), in: Capsule())
    }

    private struct PhaseItem: Identifiable {
        let phase: CyclePhase
        var id: String { phase.rawValue }
    }

    private func phaseCards(length: Int?, today: Int?) -> some View {
        let items = [CyclePhase.period, .follicular, .ovulation, .luteal].map(PhaseItem.init)
        return ForEach(items) { item in
            PhaseCard(phase: item.phase, length: length, today: today,
                      average: model.phaseAverages?[item.phase], birthControl: store.birthControl,
                      showsExercise: !model.hidesActivityNumbers, periodLength: model.periodLength)
        }
    }

    // MARK: Birth control that stops ovulation

    @ViewBuilder
    private func methodContent(_ bc: BirthControl) -> some View {
        intro(bc.hasBreakWeek
              ? "Your \(bc.inSentence) stops your body from releasing an egg, so you don't have natural phases. Your month is active days and, unless you use it continuously, a break week instead."
              : "Your \(bc.inSentence) stops your body from releasing an egg, so you don't have natural phases. Your hormones stay fairly level all month.")
        if let pack = model.packState {
            Card {
                CycleStrip(length: pack.packLength, today: pack.day,
                           color: { d in BodyLogStyle.packFill(isBreak: d > pack.activeDays, scheme) },
                           readout: { d in CycleCopy.packReadout(day: d, activeDays: pack.activeDays, packLength: pack.packLength, isToday: d == pack.day,
                                                                 activeName: model.packActiveName, breakName: model.packBreakName) },
                           startLabel: "Pack day 1", endLabel: "Day \(pack.packLength)",
                           letter: { d in pack.hasBreak && d > pack.activeDays ? "Break" : model.packActiveName })
            }
        }
        if bc.hasBreakWeek {
            let active = store.data.packActiveDays
            let length = store.data.packLength
            effectsCard(title: "Active days", subtitle: "Days 1\u{2013}\(active)", accent: .indigo, effects: CycleCopy.packEffects(isBreak: false), topic: .pillPack)
            if active < length {
                effectsCard(title: model.packBreakName, subtitle: "Days \(active + 1)\u{2013}\(length) \u{00B7} withdrawal bleed", accent: .pink, effects: CycleCopy.packEffects(isBreak: true), topic: .withdrawalBleed)
            }
        } else {
            effectsCard(title: "All month", subtitle: "No phases", accent: .indigo,
                        effects: CycleCopy.Effects(energy: "No monthly peak or dip from hormones, so changes are more likely from sleep and stress.",
                                                   sleep: "Steady from week to week.",
                                                   mood: "Steady for most. If your mood is often low, tell your doctor.",
                                                   hrv: "No monthly swing, so a drop is worth noticing.",
                                                   restingHR: "No monthly swing, so a rise is worth noticing.",
                                                   exercise: "Train as normal. There's no best or worst week."),
                        topic: nil)
        }
        LinkRow(title: "How your \(bc.inSentence) works", systemImage: "book.fill", accent: .indigo) {
            BirthControlLearnView()
        }
    }

    private func effectsCard(title: String, subtitle: String, accent: Accent, effects: CycleCopy.Effects, topic: Topic?) -> some View {
        Card(accent: accent) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.cardTitle).foregroundStyle(accent.ink(scheme))
                    Text(subtitle).font(.secondary).fontWeight(.semibold).secondaryText()
                }
                Spacer()
                if let topic { InfoButton(topic: topic).padding(.vertical, -10) }
            }
            EffectRows(effects: effects, showsExercise: !model.hidesActivityNumbers)
        }
    }

    private var termsCard: some View {
        Card {
            SectionLabel(text: "Terms on this page")
            HStack(spacing: 0) {
                ExplainedTitle(text: "HRV", topic: .hrv, size: 14)
                Spacer()
                ExplainedTitle(text: "Resting HR", topic: .restingHR, size: 14)
                Spacer()
                ExplainedTitle(text: "Wrist temp", explanation: BodyLogStyle.wristTempExplanation(ovulationStopped: model.ovulationStopped), size: 14)
            }
        }
    }
}

/// One phase with its days, her own averages (when available) and the
/// usual effects.
private struct PhaseCard: View {
    let phase: CyclePhase
    let length: Int?
    let today: Int?
    let average: AppModel.PhaseAverage?
    let birthControl: BirthControl?
    let showsExercise: Bool
    var periodLength = CycleEstimator.typicalPeriodLength
    @Environment(\.colorScheme) private var scheme

    private var topic: Topic {
        switch phase {
        case .period: .period
        case .follicular: .follicular
        case .ovulation: .ovulation
        case .luteal, .unknown: .luteal
        }
    }

    private var isNow: Bool {
        guard let today, let length else { return false }
        return CycleCopy.range(phase, length: length, periodLength: periodLength).contains(today)
    }

    var body: some View {
        let accent = BodyLogStyle.phaseAccent(phase)
        Card {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(BodyLogStyle.phaseFill(phase, scheme)).frame(width: 6, height: 38)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(BodyLogStyle.phaseName(phase, birthControl: birthControl)).font(.cardTitle)
                        if isNow, let today {
                            Text("Now \u{00B7} day \(today)")
                                .font(.small).fontWeight(.bold)
                                .foregroundStyle(BodyLogStyle.phaseOnFill(phase, scheme))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(BodyLogStyle.phaseFill(phase, scheme), in: Capsule())
                        }
                    }
                    Text(daysText).font(.secondary).fontWeight(.semibold).secondaryText()
                }
                Spacer()
                InfoButton(topic: topic).padding(.vertical, -10)
            }
            if let average { averageRow(average, accent: accent) }
            if phase == .ovulation, birthControl?.ovulation == .sometimes {
                Text("On the mini pill this may not happen every cycle.").font(.secondary).secondaryText()
            }
            EffectRows(effects: CycleCopy.effects(phase), showsExercise: showsExercise)
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(isNow ? BodyLogStyle.phaseFill(phase, scheme) : .clear, lineWidth: 2))
    }

    private var daysText: String {
        guard let length else { return "Timing varies" }
        let r = CycleCopy.range(phase, length: length, periodLength: periodLength)
        return "Days \(r.lowerBound)\u{2013}\(r.upperBound)"
    }

    private func averageRow(_ a: AppModel.PhaseAverage, accent: Accent) -> some View {
        HStack(spacing: 8) {
            stat("Sleep", a.sleepDelta == 0 ? "0m" : (a.sleepDelta > 0 ? "+" : "\u{2212}") + "\(abs(a.sleepDelta))m", accent)
            stat("Resting HR", a.restingHRDelta.map { signed($0, unit: "") } ?? "\u{2013}", accent)
            stat("HRV", a.hrvDeltaPct.map { signed($0, unit: "%") } ?? "\u{2013}", accent)
        }
        .accessibilityElement(children: .combine)
    }

    private func signed(_ v: Double, unit: String) -> String {
        let r = Int(v.rounded())
        return (r > 0 ? "+" : r < 0 ? "\u{2212}" : "") + "\(abs(r))\(unit)"
    }

    private func stat(_ label: String, _ value: String, _ accent: Accent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.small).fontWeight(.bold).secondaryText()
            Text(value).font(.cardTitle).monospacedDigit().foregroundStyle(accent.ink(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
    }
}

/// Energy, sleep, HRV, resting HR, mood and exercise lines.
private struct EffectRows: View {
    let effects: CycleCopy.Effects
    /// Off with an eating-disorder history: no exercise suggestions.
    var showsExercise = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("bolt.fill", "Energy", effects.energy, .yellow)
            row("moon.fill", "Sleep", effects.sleep, .purple)
            row("waveform.path.ecg", "HRV", effects.hrv, .indigo)
            row("heart.fill", "Resting HR", effects.restingHR, .pink)
            row("face.smiling", "Mood", effects.mood, .blue)
            if showsExercise { row("figure.run", "Exercise", effects.exercise, .mint) }
        }
    }

    private func row(_ symbol: String, _ title: String, _ text: String, _ accent: Accent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.secondary).fontWeight(.semibold)
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 26, height: 26)
                .background(accent.tint(scheme), in: Circle())
                .accessibilityHidden(true)
            (Text(title + ": ").bold() + Text(text))
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
