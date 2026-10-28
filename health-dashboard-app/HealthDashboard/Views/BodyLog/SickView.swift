import SwiftUI
import HealthCore

/// The sick check ("Might be getting sick"): which signals moved together, how sure we are,
/// what to do, and when to see a doctor. A guess, never a diagnosis.
struct SickView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

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
            Label("This is a guess, not a diagnosis. It can be wrong.", systemImage: "info.circle")
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(Accent.yellow.ink(scheme))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Accent.yellow.tint(scheme), in: Capsule())

            VStack(alignment: .leading, spacing: 0) {
                Text(headline.0)
                Text(headline.1).foregroundStyle(accent.ink(scheme))
            }
            .font(.scaled(size: 30, weight: .bold))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(summary).font(.scaled(size: 15)).secondaryText().fixedSize(horizontal: false, vertical: true)

            factorsCard
            feelingCard
            helpCard
            Card(accent: .coral) {
                Text("When to see a doctor").font(.scaled(size: 15, weight: .bold))
                Text("A fever over \(TempFormat.usesFahrenheit ? "100.4\u{00B0}F (38\u{00B0}C)" : "38\u{00B0}C (100.4\u{00B0}F)"), trouble breathing, or feeling worse after 3 days: contact your campus health center or your doctor.")
                    .font(.scaled(size: 14)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            Card(padding: 12) {
                SettingToggleRow(title: "Sick alerts", detail: "A notification, at most once a day, when the check says Possible or Likely.",
                                 systemImage: "bell.fill", accent: .pink, isOn: $store.data.sickAlerts)
            }
            Text("This feature looks for patterns in your Apple Watch data. It is not a medical device, cannot diagnose illness, and may miss things or flag you when you\u{2019}re fine.")
                .font(.scaled(size: 12)).secondaryText().fixedSize(horizontal: false, vertical: true)
            HowWeGotThisLink(title: "Sick check",
                             method: "Each morning we compare your resting heart rate, HRV, breathing rate and wrist temperature with your own last 30 days. A signal counts when it moves past a set amount: resting heart rate up 4 bpm or more, HRV down 15% or more, breathing up 1 breath a minute, wrist temperature up \(TempFormat.delta(0.4, signed: false)). Two things move these on their own, so we allow for them. In the second half of a natural cycle (luteal phase): 2 bpm more resting heart rate, 5% more HRV drop, and \(TempFormat.delta(0.6, signed: false)) for temperature. When the app can\u{2019}t tell which phase you\u{2019}re in (irregular cycles, PCOS, a cycle running longer than usual, or a method you may still ovulate on), it doesn\u{2019}t assume one: no cycle allowance is made, and the result says your cycle could be part of it. After a hard training day (active energy well above your own usual, at least 1.5 times your median of the last 2 weeks\(model.hidesActivityNumbers ? "" : " and 400 kcal or more")): 3 bpm and 10% more. The more signals move together, the likelier it is: Unlikely, Possible or Likely.")
        }
        .onChange(of: store.data.sickAlerts) { _, on in
            if on { Task { await Nudges.requestPermission() } }
        }
    }

    // MARK: Headline

    private var accent: Accent {
        switch signal.confidence {
        case .none, .low: .mint
        case .medium: .orange
        case .high: .pink
        }
    }

    private var headline: (String, String) {
        if !model.hasHeartData { return ("Sick check:", "no reading yet") }
        return switch signal.confidence {
        case .none: ("No signs", "right now")
        case .low: ("Probably nothing", "for now")
        case .medium: ("Your body\u{2019}s working", "harder than usual")
        case .high: ("Your body may be", "fighting something")
        }
    }

    private var summary: String {
        switch signal.confidence {
        case .none:
            return "Your resting heart rate, HRV, breathing and temperature look like your usual. We\u{2019}ll let you know if several of them change together."
        case .low:
            return "A signal moved a little, not enough to say you\u{2019}re getting sick. That can be stress, a late night, a hard day, or nothing at all."
        case .medium, .high:
            return "\(flaggedCount) signals moved together. That can happen a day or two before a cold. It can also be stress, a late night, drinks, or nothing at all."
        }
    }

    // MARK: Factors

    private func explanation(for name: String) -> Explanation {
        switch name {
        case "HRV": Topic.hrv.explanation
        case "Breathing rate": Topic.breathingRate.explanation
        case "Wrist temperature": BodyLogStyle.wristTempExplanation(ovulationStopped: model.ovulationStopped)
        default: Topic.restingHR.explanation
        }
    }

    /// The change as shown: wrist temperature in her own unit (°F in the
    /// US), the rest as the check worked them out.
    private func changeText(_ f: IllnessSignal.Factor) -> String {
        if f.name == "Wrist temperature", let t = model.wristTempDelta { return TempFormat.delta(t) }
        return f.change
    }

    private var factorsCard: some View {
        Card {
            HStack {
                SectionLabel(text: "What we noticed")
                Spacer()
                Text(signal.confidence.rawValue)
                    .font(.scaled(size: 12, weight: .bold))
                    .foregroundStyle(accent.ink(scheme))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(accent.tint(scheme), in: Capsule())
                InfoButton(topic: .illness).padding(.vertical, -12)
            }
            if model.hasHeartData {
                ForEach(signal.factors, id: \.self) { f in
                    factorRow(f)
                }
            } else {
                Text("No resting heart rate or HRV from today or yesterday yet, so there\u{2019}s nothing to compare. Wear your Watch to bed tonight.")
                    .font(.scaled(size: 14)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            if let caveat = cycleCaveat {
                Text(caveat).font(.scaled(size: 13)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            if signal.factors.count < 4 {
                Text("Breathing rate and wrist temperature need your Apple Watch on overnight (Series 8 or later for temperature).")
                    .font(.scaled(size: 12)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func factorRow(_ f: IllnessSignal.Factor) -> some View {
        let a: Accent = f.flagged ? .pink : .mint
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: f.flagged ? "exclamationmark" : "checkmark")
                .font(.scaled(size: 12, weight: .heavy))
                .foregroundStyle(a.ink(scheme))
                .frame(width: 28, height: 28)
                .background(a.tint(scheme), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(f.name).font(.scaled(size: 15, weight: .bold))
                    InfoButton(explanation: explanation(for: f.name)).padding(.vertical, -12)
                    Spacer()
                    Text(changeText(f)).font(.scaledNumber(16)).foregroundStyle(f.flagged ? a.ink(scheme) : Palette(scheme: scheme).primary)
                }
                Text(f.note ?? (f.flagged ? flaggedText(f.name) : "Within your normal range."))
                    .font(.scaled(size: 13)).secondaryText()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func flaggedText(_ name: String) -> String {
        switch name {
        case "HRV": return "Lower than your usual by more than normal. Counts toward the signal."
        case "Breathing rate": return "Faster than your usual. Counts toward the signal."
        case "Wrist temperature": return "Warmer than your usual. Counts toward the signal."
        default: return "Higher than your usual by more than normal. Counts toward the signal."
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
        if case let .phases(_, _, phase) = model.cycleDisplay {
            if phase == .luteal {
                parts.append("You\u{2019}re in the second half of your cycle (luteal phase), which raises resting heart rate and wrist temperature and lowers HRV on its own. The check allows 2 bpm, 5% HRV and \(TempFormat.delta(0.6, signed: false)) temperature for that today.")
            } else {
                parts.append("In the second half of your cycle the check allows for the rise in resting heart rate and temperature that comes with it. That doesn\u{2019}t apply today.")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Feelings

    /// Today's entry in the shared symptom log (the cycle log uses calendar
    /// days too, so both screens edit the same entry).
    private var todaysSymptoms: [String] {
        store.data.symptomLog.last { Calendar.current.isDateInToday($0.date) }?.symptoms ?? []
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

    private var feelingCard: some View {
        Card {
            SectionLabel(text: "Feeling anything? Log it")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Self.feelings, id: \.self) { f in
                    Chip(title: f, selected: todaysSymptoms.contains(f), accent: .pink) { toggle(f) }
                }
                Chip(title: "I feel fine", selected: !todaysSymptoms.contains { Self.sickOnly.contains($0) }, accent: .mint) { feelFine() }
            }
            let sharedOn = Self.feelings.filter { Self.shared.contains($0) && todaysSymptoms.contains($0) }
            if !sharedOn.isEmpty {
                Text("\(sharedOn.joined(separator: " and ")) \(sharedOn.count == 1 ? "is" : "are") also in your cycle log, so \u{201C}I feel fine\u{201D} keeps \(sharedOn.count == 1 ? "it" : "them"). Tap to remove.")
                    .font(.scaled(size: 12)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            Text("Saved with today\u{2019}s symptoms. Your answers help you see when these guesses are right for you.")
                .font(.scaled(size: 12)).secondaryText().fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Help

    private var helpCard: some View {
        Card(accent: .mint) {
            SectionLabel(text: signal.confidence == .none ? "If you start to feel unwell" : "Things that may help", accent: .mint)
            // The same plan Today and Sleep show. Tonight's need already adds
            // 30 minutes when the check says Possible or Likely.
            tip("moon.fill", "Sleep early tonight. \(model.tonightAimSentence)" + (model.unwellTonight ? "" : " Add about 30 minutes if you feel unwell."))
            tip("drop.fill", "Extra water, and skip drinks for a few days.")
            tip("leaf.fill", model.hidesEffortTargets ? "Take it easy today and rest when you can." : "Keep today easy: skip hard training until you feel better.")
            tip("pills", "Some people take vitamin C or zinc at the first sign of a cold. Evidence that it helps is mixed, so ask a pharmacist first.")
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Accent.mint.ink(scheme)).frame(width: 22).accessibilityHidden(true)
            Text(text).font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
