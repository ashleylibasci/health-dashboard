import SwiftUI
import HealthCore

/// "Why do I feel off?": the likeliest reasons today feels harder than usual,
/// ranked, each with a plain explanation and one concrete thing to try.
struct WhyOffView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let reasons = model.whyOffReasons
        Screen(title: "Why do I feel off?", accent: .coral) {
            SampleDataBanner()
            headerCard(reasons)
            if reasons.isEmpty {
                allClearCard
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(reasons.enumerated()), id: \.element.id) { i, r in
                        WhyOffReasonRow(number: i + 1, reason: r, tryThis: model.tryThis(for: r))
                    }
                }
                if let top = reasons.first {
                    oneThingCard(top, second: reasons.dropFirst().first)
                }
            }
            matchCard
            HowWeGotThisLink(title: "Why you might feel off",
                             method: "We check your sleep debt, recent late nights, where you are in your cycle, signs you might be getting sick, stress, caffeine timing and daylight, each against your own normal. The ones furthest from your normal rank highest. These are best guesses, not a diagnosis.")
                .padding(.horizontal, 4)
        }
    }

    // MARK: Header

    private func headerCard(_ reasons: [AppModel.OffReason]) -> some View {
        let recovery = model.recoveryShown
        let usual = model.recoveryUsual
        let below = recovery.map { $0 < usual - 5 } ?? false
        let usualWord = model.recoveryUsualIsPersonal ? "your usual" : "typical"
        let pill = recovery.map { "Recovery \($0) · \(usualWord) \(usual)" } ?? "No recovery yet today"
        return Card(accent: .coral) {
            HStack(spacing: 0) {
                Text(pill)
                    .font(.scaled(size: 13, weight: .bold))
                    .foregroundStyle((below ? Accent.coral : Accent.mint).ink(scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((below ? Accent.coral : Accent.mint).tint(scheme), in: Capsule())
                InfoButton(topic: .recovery)
            }
            Text(reasons.isEmpty ? "Nothing stands out today" : "Why you might feel off today")
                .font(.scaled(size: 26, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(reasons.isEmpty
                 ? "Your sleep, heart and other signals are close to your normal."
                 : "Your top reasons, ranked by how far each one is from your normal. Tap ⓘ to learn what each means.")
                .font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var allClearCard: some View {
        Card(accent: .mint) {
            Image(systemName: "checkmark.seal.fill")
                .font(.scaled(size: 28, weight: .semibold))
                .foregroundStyle(Accent.mint.ink(scheme))
                .accessibilityHidden(true)
            Text("All clear").font(.scaled(size: 20, weight: .bold))
            Text("No sleep debt to speak of, no recent late nights, and no signs your body is fighting something. If you still feel off, it may be something a watch can't measure: a hard day, skipped meals, not enough water, or just a slow morning.")
                .font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Text("Try a glass of water, something to eat and 10 minutes outside.")
                .font(.scaled(size: 14, weight: .semibold))
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
            Text(model.tryThis(for: top)).font(.scaled(size: 18, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            if both {
                Text("It helps with your top two reasons at once.").font(.scaled(size: 13)).secondaryText()
            }
        }
    }

    private var matchCard: some View {
        Card {
            Text("Does this match how you feel?").font(.scaled(size: 17, weight: .bold))
            Text("Telling the app how awake you feel each morning makes the next guess better.")
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "Do your morning check-in", systemImage: "checkmark.circle.fill", accent: .indigo) { CheckInView() }
            LinkRow(title: "The cost of a late night", systemImage: "moon.haze.fill", accent: .purple) { LateNightView() }
            Text("Best guesses from your own data, not a diagnosis. See a doctor if you feel unwell.")
                .font(.scaled(size: 12)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Subviews

private struct WhyOffReasonRow: View {
    var number: Int
    var reason: AppModel.OffReason
    var tryThis: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent: Accent = number == 1 ? .coral : (number == 2 ? .orange : .indigo)
        Card {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)")
                    .font(.scaled(size: 14, weight: .heavy))
                    .foregroundStyle(accent.ink(scheme))
                    .frame(width: 30, height: 30)
                    .background(accent.tint(scheme), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(reason.title).font(.scaled(size: 16, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        if let topic = reason.topic {
                            InfoButton(topic: topic).padding(.vertical, -12)
                        }
                    }
                    Text(reason.detail).font(.scaled(size: 14)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .accessibilityHidden(true)
                (Text("Try this: ").font(.scaled(size: 14, weight: .bold)) + Text(tryThis).font(.scaled(size: 14)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Accent.yellow.tint(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
