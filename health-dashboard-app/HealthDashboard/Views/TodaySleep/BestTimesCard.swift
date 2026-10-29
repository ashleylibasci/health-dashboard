import SwiftUI
import HealthCore

/// "Your best sleep times" on the Sleep tab, right under last night: tonight's
/// bed-by and wake time (the same two Today, the Watch and the smart alarm
/// use), the window they come from, and one line on why. The whole card
/// opens the Sleep plan.
struct BestTimesCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let p = Palette(scheme: scheme)
        let best = model.bestTimes
        let plan = model.tonightPlan
        let status = BestTimesText.status(best, isExample: model.usingSampleData)
        NavigationLink {
            WakePlanView()
        } label: {
            Card(accent: .purple) {
                HStack(spacing: Space.s) {
                    CapsLabel("Your best sleep times", color: Accent.purple.ink(scheme))
                    Spacer(minLength: Space.xs)
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(p.tertiary)
                }
                AdaptiveStack(spacing: Space.m, alignment: .top) {
                    column("Bed by", model.tonightBedtime, note: "Best \(best.bed.label)")
                    column("Up at", plan.wake ?? plan.upBy, note: BestTimesText.alarmNote(model, plan: plan))
                }
                StatusChip(status: status)
                Text(BestTimesText.line(model))
                    .font(.bodyText)
                    .foregroundStyle(p.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(best, plan: plan, status: status))
        .accessibilityHint("Opens your sleep plan")
        .accessibilityAddTraits(.isButton)
    }

    private func column(_ title: String, _ time: Minutes, note: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            CapsLabel(title, isHeader: false)
            ClockText(minutes: time, role: .numberL)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(note)
                .font(.secondary)
                .foregroundStyle(Palette(scheme: scheme).secondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: typeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
    }

    private func spoken(_ best: SleepTiming.Result, plan: TonightPlan, status: SummaryStatus) -> String {
        ["Your best sleep times, \(status.text)",
         "Bed by \(Clock.format(model.tonightBedtime)), best window \(best.bed.label)",
         "Up at \(Clock.format(plan.wake ?? plan.upBy)), \(BestTimesText.alarmNote(model, plan: plan))",
         BestTimesText.line(model)].joined(separator: ". ")
    }
}

/// The best-times wording, shared by the Sleep tab card and the Sleep plan
/// so they always say the same thing.
@MainActor
enum BestTimesText {
    /// The chip: how sure the window is, or that there's no clear pattern.
    /// On example data it says so instead of counting nights next to
    /// example bars (design flaw 6).
    static func status(_ r: SleepTiming.Result, isExample: Bool) -> SummaryStatus {
        if isExample { return SummaryStatus(text: "Example", accent: .yellow) }
        switch r.confidence {
        case .fair: return SummaryStatus(text: "Fairly sure", accent: .mint)
        case .early: return SummaryStatus(text: "Early read", accent: .yellow)
        case .learning:
            if r.nightsUsed < r.nightsNeeded {
                return SummaryStatus(text: "Learning \(r.nightsUsed) of \(r.nightsNeeded)", accent: .purple)
            }
            switch r.caveat {
            case .usualWorks: return SummaryStatus(text: "Usual time works", accent: .mint)
            case .some: return SummaryStatus(text: "No clear pattern", accent: .indigo)
            case .none: return SummaryStatus(text: "From your need", accent: .purple)
            }
        }
    }

    /// The one line: her own finding, else why tonight is earlier than
    /// her window, else what's holding the finding back, else what the
    /// window is based on. The rest is in `otherLines`.
    static func line(_ model: AppModel) -> String {
        lines(model).first ?? model.bestTimes.why
    }

    /// Everything the one line could have said, after it (for the ⓘ).
    static func otherLines(_ model: AppModel) -> [String] { Array(lines(model).dropFirst()) }

    private static func lines(_ model: AppModel) -> [String] {
        let r = model.bestTimes
        var out: [String] = []
        if r.evidence != nil { out.append(r.why) }
        if let earlier = earlierReason(model) { out.append(earlier) }
        if let caveat = r.caveat { out.append(caveat.text) }
        if r.evidence == nil { out.append(r.why) }
        return out
    }

    /// Why tonight is earlier than her usual best: "Tonight 30 min earlier
    /// to pay back sleep debt." Nil on an ordinary night.
    static func earlierReason(_ model: AppModel) -> String? {
        let earlier = model.tonightEarlierThanBest
        guard earlier > 0 else { return nil }
        let extra = model.tonightNeed.parts.dropFirst().filter { $0.minutes > 0 }.max { $0.minutes < $1.minutes }
        let why: String = switch extra?.label {
        case "Paying back sleep debt": "to pay back sleep debt"
        case "Days around your period": "for the days around your period"
        case "Hard day": "after a hard day"
        case "Fighting something off": "in case you're fighting something off"
        default: "for tonight's extra sleep"
        }
        // "Bed by" is the end of her best window on an ordinary night, so
        // tonight can still sit inside the window: say earlier than usual.
        return "Tonight \(Clock.duration(earlier)) earlier than usual, \(why)."
    }

    /// Under "Up at": the smart alarm window, or that it's off.
    static func alarmNote(_ model: AppModel, plan: TonightPlan) -> String {
        guard model.store.data.smartAlarmEnabled, let w = plan.alarmWindow else { return "Smart alarm off" }
        return "Alarm \(w.label)"
    }

    /// "9 of your last 14 nights were within 30 minutes of this."
    static func regularity(_ r: SleepTiming.Result) -> String? {
        guard r.regularityOf >= 5 else { return nil }
        var text = "\(r.regularityHits) of your last \(r.regularityOf) nights you fell asleep within 30 minutes of this window."
        if let sd = r.onsetSD, sd > 60 {
            text += " Your bedtime moved about \(Clock.duration(sd)) night to night; keeping it within 30 minutes may matter as much as the exact time."
        }
        return text
    }
}
