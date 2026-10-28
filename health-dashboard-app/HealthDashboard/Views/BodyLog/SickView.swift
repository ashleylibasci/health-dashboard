import SwiftUI
import HealthCore

/// The sick check: does she look sick or not, from which signals moved
/// together. A guess, never a diagnosis. Logging how she feels, what may
/// help, and being sick on her birth control are one tap down.
struct SickView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var explaining: Explanation? = nil

    static let feelings = ["Sore throat", "Stuffy nose", "Fatigue", "Headache", "Cough", "Fever"]
    /// Also on the cycle symptom log, so "I feel fine" leaves them alone.
    static let shared: Set<String> = ["Fatigue", "Headache"]
    /// Only logged here.
    static var sickOnly: [String] { feelings.filter { !shared.contains($0) } }

    private var signal: IllnessSignal { model.illness }
    private var flaggedCount: Int { signal.factors.filter(\.flagged).count }

    var body: some View {
        Screen(title: "Sick check", accent: .pink) {
            SampleDataBanner()
            SummaryHeader(eyebrow: "Sick check", value: headline, status: status, line: summary.line,
                          accent: accent, info: info)
            if model.hasHeartData {
                RowCard {
                    ForEach(Array(signal.factors.enumerated()), id: \.element) { i, f in
                        if i > 0 { RowDivider() }
                        factorRow(f)
                    }
                    if let caveat = cycleCaveat {
                        RowDivider()
                        ExpandRow(title: "Allowed for today", summary: caveatSummary, systemImage: "slider.horizontal.3", accent: .indigo) {
                            Text(caveat).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if signal.factors.count < 4 {
                        RowDivider()
                        ExpandRow(title: "Why only \(signal.factors.count) signals", summary: "Breathing and temperature need your Watch overnight",
                                  systemImage: "applewatch", accent: .indigo) {
                            Text("Breathing rate and wrist temperature need your Apple Watch on overnight. Temperature needs a Series 8 or later, any Ultra, or SE 3, and about 5 nights to set a baseline.")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Text(([summary.rest] + ["This is a guess, not a diagnosis. It can be wrong."]).compactMap { $0 }.joined(separator: " "))
                .font(.secondary).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            RowCard {
                ExpandRow(title: "Feeling anything? Log it", summary: feelingSummary, systemImage: "hand.raised.fill", accent: .pink) {
                    feelingLog
                }
                RowDivider()
                ExpandRow(title: "Things that may help", summary: "Sleep, water and an easy day", systemImage: "leaf.fill", accent: .mint) {
                    helpTips
                }
                // Being sick on her method, only while she may be sick.
                if mayBeSick, let article = GuideArticle.sickOnMethod(for: store.birthControl) {
                    RowDivider()
                    MetricRow(title: article.title, note: article.summary, systemImage: "pills.fill", accent: .purple) {
                        GuideArticleView(article: article)
                    }
                }
            }
        }
        .sheet(item: $explaining) { ExplanationSheet(explanation: $0) }
    }

    // MARK: Headline

    private var accent: Accent {
        if feelsSick { return .coral }
        return switch signal.confidence {
        case .none, .low: .mint
        case .medium: .orange
        case .high: .coral
        }
    }

    /// She logged a fever, sore throat or cough today.
    private var feelsSick: Bool { !model.loggedSickSymptoms.isEmpty }

    /// She feels sick, or the check found a couple of signs or several.
    private var mayBeSick: Bool { feelsSick || model.unwellTonight }

    private var headline: String {
        if feelsSick { return "You feel sick" }
        if !model.hasHeartData { return "No reading yet" }
        return switch signal.confidence {
        case .none: "No signs"
        case .low: "Probably nothing"
        case .medium: "Working harder"
        case .high: "May be fighting something"
        }
    }

    private var status: SummaryStatus? {
        guard model.hasHeartData, !feelsSick else { return nil }
        return SummaryStatus(text: signal.confidence.rawValue, accent: accent)
    }

    /// The answer in one sentence (`line`), and what's left of the old
    /// summary (`rest`), which goes in the caption under the signals.
    private var summary: (line: String, rest: String?) {
        if feelsSick {
            let logged = model.loggedSickSymptoms.map { $0.lowercased() }.joined(separator: " and ")
            return ("You logged \(logged) today. Your Watch can lag behind, so trust how you feel.", nil)
        }
        if !model.hasHeartData {
            return ("No resting heart rate or HRV from today or yesterday yet. Wear your Watch to bed tonight.", nil)
        }
        switch signal.confidence {
        case .none:
            return ("Your resting heart rate, HRV, breathing and temperature look like your usual.",
                    "We\u{2019}ll let you know if several of them change together.")
        case .low:
            return ("A signal moved a little, not enough to say you\u{2019}re getting sick.",
                    "That can be stress, a late night, a hard day, or nothing at all.")
        case .medium, .high:
            return ("\(flaggedCount) signals moved together. That can happen a day or two before a cold.",
                    "It can also be stress, a late night, drinks, or nothing at all.")
        }
    }

    /// The ⓘ on the header: what the check is, with how it's worked out.
    private var info: Explanation {
        let topic = Topic.illness.explanation
        return Explanation(id: topic.id, title: topic.title, meaning: topic.meaning, forYou: topic.forYou,
                           howWeGotIt: "Each morning we compare your resting heart rate, HRV, breathing rate and wrist temperature with your own last 30 days. A signal counts when it moves past a set amount: resting heart rate up 4 bpm or more, HRV down 15% or more, breathing up 1 breath a minute, wrist temperature up \(TempFormat.delta(0.4, signed: false)). If your resting heart rate or HRV normally moves a lot from day to day, the amount is bigger for you: twice your usual spread for resting heart rate, one and a half times for HRV. Some things move these on their own, so we allow for them. In the second half of a natural cycle (luteal phase): 2 bpm more resting heart rate, 5% more HRV drop, and \(TempFormat.delta(0.6, signed: false)) for temperature. In the first week of a natural period resting heart rate runs a little low, so the amounts are 1 bpm and 3% smaller then. On the pill, ring, patch, implant or shot there\u{2019}s no cycle swing to allow for. When the app can\u{2019}t tell which phase you\u{2019}re in (irregular cycles, PCOS, a cycle running longer than usual, or a method you may still ovulate on), it doesn\u{2019}t assume one: no cycle allowance is made, and the result says your cycle could be part of it. After a hard training day (active energy at least 1.5 times your median of the last 2 weeks, and at least about 5 calories per kg of your weight): 3 bpm and 10% more. The result counts how many signals moved together (a little off, a couple of signs, several signs). It isn\u{2019}t a chance of being sick. It is not a medical device, and it may miss things or flag you when you\u{2019}re fine.")
    }

    // MARK: Signals

    private func explanation(for name: String) -> Explanation {
        switch name {
        case "HRV": model.hrvExplanation
        case "Breathing rate": Topic.breathingRate.explanation
        case "Wrist temperature": BodyLogStyle.wristTempExplanation(ovulationStopped: model.ovulationStopped)
        default: model.restingHRExplanation
        }
    }

    /// The change as shown: wrist temperature in her own unit (°F in the
    /// US), the rest as the check worked them out.
    private func changeText(_ f: IllnessSignal.Factor) -> String {
        if f.name == "Wrist temperature", let t = model.wristTempDelta { return TempFormat.delta(t) }
        return f.change
    }

    /// A row per signal: coral "Moved" when it counts, mint "Usual" when it
    /// doesn't (coral means "worse than usual" everywhere, Tanaka F1). The
    /// row opens what the signal means.
    private func factorRow(_ f: IllnessSignal.Factor) -> some View {
        let a: Accent = f.flagged ? .coral : .mint
        return MetricRow(title: f.name, note: factorNote(f), value: changeText(f),
                         verdict: RowVerdict(text: f.flagged ? "Moved" : "Usual", accent: a),
                         systemImage: f.flagged ? "exclamationmark" : "checkmark", accent: a) {
            explaining = explanation(for: f.name)
        }
    }

    /// Why a signal that moved doesn't count ("Expected in this phase of
    /// your cycle"), or which way it moved.
    private func factorNote(_ f: IllnessSignal.Factor) -> String? {
        if let note = f.note {
            return note.hasPrefix("Could be your cycle") ? "Could be your cycle" : note
        }
        guard f.flagged else { return nil }
        switch f.name {
        case "HRV": return "Lower than your usual"
        case "Breathing rate": return "Faster than your usual"
        case "Wrist temperature": return "Warmer than your usual"
        default: return "Higher than your usual"
        }
    }

    /// The allowances the check is using today: the luteal phase of a
    /// natural cycle (or a cycle whose phase can't be told), and a hard
    /// training day yesterday.
    private var cycleCaveat: String? {
        var parts: [String] = []
        if model.hardTrainingYesterday {
            parts.append("Yesterday\u{2019}s active energy was well above your usual, which raises resting heart rate and lowers HRV the next morning, so the check allows 3 bpm and 10% more today.")
        }
        if signal.cyclePhaseUnknown {
            // Only point at "this" when something moved (round 3: "All clear"
            // followed by "part of this could be your cycle").
            parts.append("The app can\u{2019}t tell which phase of your cycle you\u{2019}re in, so it doesn\u{2019}t allow for one today. The second half of a cycle can raise resting heart rate and temperature and lower HRV on its own"
                         + (signal.confidence == .none ? "." : ", so part of this could be your cycle."))
        }
        if model.cycleHeartShift == .period {
            parts.append("In the first week of your period resting heart rate runs a little low on its own, so the check counts a slightly smaller rise today (1 bpm and 3% less).")
        } else if case let .phases(_, _, phase) = model.cycleDisplay {
            if phase == .luteal {
                parts.append("You\u{2019}re in the second half of your cycle (luteal phase), which raises resting heart rate and wrist temperature and lowers HRV on its own. The check allows 2 bpm, 5% HRV and \(TempFormat.delta(0.6, signed: false)) temperature for that today.")
            } else {
                parts.append("In the second half of your cycle the check allows for the rise in resting heart rate and temperature that comes with it. That doesn\u{2019}t apply today.")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var caveatSummary: String {
        var parts: [String] = []
        if model.hardTrainingYesterday { parts.append("Yesterday\u{2019}s training") }
        if signal.cyclePhaseUnknown || model.cycleHeartShift == .period || model.inLutealPhase { parts.append("your cycle") }
        guard let first = parts.first else { return "Your cycle" }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: " and ")
    }

    // MARK: Feelings

    /// Today's entry in the shared symptom log (the cycle log uses calendar
    /// days too, so both screens edit the same entry).
    private var todaysSymptoms: [String] {
        store.data.symptomLog.last { Calendar.current.isDateInToday($0.date) }?.symptoms ?? []
    }

    private var feelingSummary: String {
        let logged = Self.feelings.filter { todaysSymptoms.contains($0) }
        return logged.isEmpty ? "Sore throat, fever, cough\u{2026}" : "Today: " + logged.joined(separator: ", ").lowercased()
    }

    private func toggle(_ feeling: String) {
        var data = store.data
        let cal = Calendar.current
        var list = todaysSymptoms
        if let i = list.firstIndex(of: feeling) { list.remove(at: i) } else { list.append(feeling) }
        data.symptomLog.removeAll { cal.isDateInToday($0.date) }
        if !list.isEmpty { data.symptomLog.append(.init(date: .now, symptoms: list)) }
        store.data = data
    }

    /// Clears the cold-type symptoms only. Headache and fatigue are shared
    /// with the cycle log, so they stay until she taps them off.
    private func feelFine() {
        var data = store.data
        let cal = Calendar.current
        let kept = todaysSymptoms.filter { !Self.sickOnly.contains($0) }
        data.symptomLog.removeAll { cal.isDateInToday($0.date) }
        if !kept.isEmpty { data.symptomLog.append(.init(date: .now, symptoms: kept)) }
        store.data = data
    }

    @ViewBuilder
    private var feelingLog: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Self.feelings, id: \.self) { f in
                Chip(title: f, selected: todaysSymptoms.contains(f), accent: .pink) { toggle(f) }
            }
            Chip(title: "I feel fine", selected: !todaysSymptoms.contains { Self.sickOnly.contains($0) }, accent: .mint) { feelFine() }
        }
        let sharedOn = Self.feelings.filter { Self.shared.contains($0) && todaysSymptoms.contains($0) }
        if !sharedOn.isEmpty {
            Text("\(sharedOn.joined(separator: " and ")) \(sharedOn.count == 1 ? "is" : "are") also in your cycle log, so \u{201C}I feel fine\u{201D} keeps \(sharedOn.count == 1 ? "it" : "them"). Tap to remove.")
                .font(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Text("Saved with today\u{2019}s symptoms. Your answers help you see when these guesses are right for you.")
            .font(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Help

    @ViewBuilder
    private var helpTips: some View {
        // She said she feels sick: the Watch can lag behind (round 4, Moreno F1).
        if feelsSick {
            tip("thermometer.medium", "Take your temperature with a thermometer. Wrist temperature isn\u{2019}t a fever reading.")
        }
        // The same plan Today and Sleep show. Tonight's need already adds
        // 30 minutes when the check finds a couple of signs or several.
        tip("moon.fill", "Sleep early tonight. \(model.tonightAimSentence)" + (model.unwellTonight ? "" : " Add about 30 minutes if you feel unwell."))
        tip("drop.fill", "Extra water, and skip alcohol for a few days.")
        tip("leaf.fill", model.hidesEffortTargets ? "Take it easy today and rest when you can." : "Keep today easy: skip hard training until you feel better.")
        tip("pills", "Some people take vitamin C or zinc at the first sign of a cold. Evidence that it helps is mixed, so ask a pharmacist first.")
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Accent.mint.ink(scheme)).frame(width: 22).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
