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

    private func header(_ reasons: [AppModel.OffReason]) -> some View {
        let recovery = model.recoveryShown
        let below = recovery.map { $0 < model.recoveryUsual - 5 } ?? false
        let usualWord = model.recoveryUsualIsPersonal ? "usual" : "start"
        return SummaryHeader(eyebrow: reasons.isEmpty ? "Why you might feel off" : "Most likely",
                             value: reasons.first?.title ?? "Nothing stands out",
                             status: recovery.map { SummaryStatus(text: "Recovery \($0)", accent: below ? .coral : .mint) },
                             line: reasons.isEmpty
                                ? "Your sleep, heart and other signals are close to your normal."
                                : model.usingSampleData
                                    ? "Example reasons, ranked by how far each one is from the example normal."
                                    : "Your top reasons, ranked by how far each one is from your normal.",
                             pairs: recovery == nil ? [] : [StatPair(label: "Recovery \(usualWord)", value: "\(model.recoveryUsual)")],
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
        return Card(accent: .indigo) {
            SectionLabel(text: "The one thing to do", accent: .indigo)
            Text(model.tryThis(for: top)).font(.cardTitle)
                .fixedSize(horizontal: false, vertical: true)
            if both {
                Text("It helps with your top two reasons at once.").font(.secondary).secondaryText()
            }
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
        ExpandRow(title: reason.title, summary: reason.detail,
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
