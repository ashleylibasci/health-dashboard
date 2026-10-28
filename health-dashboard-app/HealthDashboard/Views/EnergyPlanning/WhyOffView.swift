import SwiftUI
import HealthCore

/// "Why do I feel off?": the likeliest reason today feels harder than
/// usual, the one thing to do about it, and the other reasons as rows.
struct WhyOffView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let reasons = model.whyOffReasons
        Screen(title: "Why do I feel off?", accent: .coral) {
            SampleDataBanner()
            header(reasons)
            if reasons.isEmpty {
                allClearCard
            } else {
                // The top reason's tip is the one thing to do, shown once,
                // first; the other reasons keep their own (Whitfield F14).
                if let top = reasons.first {
                    oneThingCard(top, second: reasons.dropFirst().first)
                }
                RowCard {
                    ForEach(Array(reasons.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { RowDivider() }
                        WhyOffReasonRow(number: i + 1, reason: r, tryThis: i == 0 ? nil : model.tryThis(for: r))
                    }
                }
            }
        }
    }

    // MARK: Header

    /// How the reasons are picked, behind the header's ⓘ.
    private var info: Explanation {
        Explanation(id: "whyOff", title: "Why you might feel off",
                    meaning: "We check your sleep debt, recent late nights, where you are in your cycle, signs you might be getting sick, stress, caffeine timing and daylight, each against your own normal. The ones furthest from your normal rank highest.",
                    forYou: (model.usingSampleData
                             ? "Worked out from example data until your own nights come in. Not a diagnosis."
                             : "Best guesses from your own data, not a diagnosis.")
                        + " Telling the app how awake you feel each morning makes the next guess better.")
    }

    /// No stat pair: a lone "Recovery start 78" read as jargon (F13); the
    /// badge already compares today's recovery with her usual.
    private func header(_ reasons: [AppModel.OffReason]) -> some View {
        let recovery = model.recoveryShown
        let below = recovery.map { $0 < model.recoveryUsual - 5 } ?? false
        return SummaryHeader(eyebrow: reasons.isEmpty ? "Why you might feel off" : "Most likely",
                             value: reasons.first?.title ?? "Nothing stands out",
                             status: recovery.map { SummaryStatus(text: "Recovery \($0)", accent: below ? .coral : .mint) },
                             line: reasons.isEmpty
                                ? "Your sleep, heart and other signals are close to your normal."
                                : model.usingSampleData
                                    ? "Example reasons, ranked by how far each one is from the example normal."
                                    : "Your top reasons, ranked by how far each one is from your normal.",
                             accent: .coral, info: info)
    }

    private var allClearCard: some View {
        Card(accent: .mint) {
            Text("No sleep debt to speak of, no recent late nights, and no signs your body is fighting something. If you still feel off, it may be something a watch can't measure: a hard day, skipped meals, not enough water, or just a slow morning.")
                .font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Text("Try a glass of water, something to eat and 10 minutes outside.")
                .font(.bodyEmphasis)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func oneThingCard(_ top: AppModel.OffReason, second: AppModel.OffReason?) -> some View {
        let bedtimeFix: Set<Topic> = [.sleepDebt, .lateNight]
        let both = second.map { s in
            bedtimeFix.contains(top.topic ?? .daylight) && bedtimeFix.contains(s.topic ?? .daylight)
        } ?? false
        // One line to act on; the arithmetic behind it opens in place (F14).
        return RowCard(accent: .indigo) {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionLabel(text: "The one thing to do", accent: .indigo)
                Text(headline(for: top)).font(.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            RowDivider(hasIcon: false)
            ExpandRow(title: "Why this helps", summary: both ? "It helps with your top two reasons at once" : nil,
                      accent: .indigo) {
                Text(model.tryThis(for: top)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The one thing to do, in a few words. The full tip (`tryThis`) is in
    /// the row under it.
    private func headline(for reason: AppModel.OffReason) -> String {
        switch reason.topic {
        case .sleepDebt?: return "Bed by \(Clock.format(model.tonightAimBedtime)) tonight"
        case .lateNight?: return "Bed by \(Clock.format(model.tonightBedtime)) tonight and tomorrow"
        case .luteal?: return "Extra rest is fine right now"
        case .illness?: return "Take an easy day"
        case .stress?: return "Five minutes of slow breathing"
        case .caffeineCutoff?:
            return model.caffeineCutoffBeforeWake
                ? "One small drink, soon after you wake"
                : "Last caffeine before \(Clock.format(model.caffeineCutoff)) tomorrow"
        case .daylight?: return "10 to 20 minutes outside"
        default: return "Go easy on yourself today"
        }
    }
}

// MARK: - Subviews

/// One reason as a row that opens in place: its detail, its tip and what
/// the term means.
private struct WhyOffReasonRow: View {
    var number: Int
    var reason: AppModel.OffReason
    var tryThis: String?
    @Environment(\.colorScheme) private var scheme
    @State private var explaining: Explanation? = nil

    var body: some View {
        ExpandRow(title: reason.title, summary: reason.detail, summaryLines: 2,
                  systemImage: "\(number).circle.fill", accent: number == 1 ? .coral : (number == 2 ? .orange : .indigo)) {
            Text(reason.detail).fixedSize(horizontal: false, vertical: true)
            if let tryThis {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.secondary).fontWeight(.semibold)
                        .foregroundStyle(Accent.yellow.ink(scheme))
                        .accessibilityHidden(true)
                    (Text("Try this: ").font(.role(.bodyEmphasis)) + Text(tryThis).font(.role(.bodyText)))
                        .foregroundStyle(Palette(scheme: scheme).primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let topic = reason.topic {
                Button("What \(reason.title.lowercased()) means") { explaining = topic.explanation }
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minHeight: Sizes.minTap, alignment: .leading)
            }
        }
        .sheet(item: $explaining) { ExplanationSheet(explanation: $0) }
    }
}
