import SwiftUI
import HealthCore

/// One thing the app learns from her own data, and how far along it is.
struct LearningItem: Identifiable, Hashable {
    var id: String { title }
    var title: String
    /// Her own nights or days so far, and how many it needs.
    var have: Int
    var need: Int
    /// "nights", "days", "mornings".
    var unit: String
    /// Still on example numbers (shows "Example" instead of a count).
    var isExample = false
    /// Ready for a reason other than the count (the body clock).
    var readyOverride: Bool? = nil

    var isReady: Bool { readyOverride ?? (!isExample && have >= need) }
    var progress: Double { isReady ? 1 : isExample ? 0 : min(Double(have) / Double(max(need, 1)), 1) }

    /// "Ready", "Example", "3 days to go", "9 of 14 nights".
    var status: String {
        if isReady { return "Ready" }
        if isExample { return "Example" }
        if unit == "days", need - have <= 6 { return need - have == 1 ? "Ready tomorrow" : "Ready in \(need - have) days" }
        return "\(have) of \(need) \(unit)"
    }
}

extension AppModel {
    /// Everything that calibrates to her, in the order it usually gets
    /// ready (D-L1). On example data the counts that would be about
    /// example nights read "Example".
    var learningItems: [LearningItem] {
        let example = usingSampleData
        let earlier = nights.filter { $0.wakeDay < lastNightWakeDay && isRealNight($0) }
        let heartDays = earlier.filter { $0.outcome.hrvDeltaPct != nil || $0.outcome.restingHRDelta != nil }.count
        let best = bestTimes
        let caffeine = cutoffTest
        return [
            LearningItem(title: "Your usual recovery", have: min(heartDays, 7), need: 7, unit: "days",
                         isExample: example, readyOverride: recoveryUsualIsPersonal ? true : nil),
            LearningItem(title: "Your usual energy", have: min(earlier.count, 7), need: 7, unit: "days",
                         isExample: example, readyOverride: energyUsualIsPersonal ? true : nil),
            LearningItem(title: "Sleep need", have: min(realNightCount, Self.nightsNeeded), need: Self.nightsNeeded,
                         unit: "nights", isExample: example),
            LearningItem(title: "Best wake window", have: min(mornings.count, 10), need: 10, unit: "mornings",
                         isExample: example),
            LearningItem(title: "Body clock", have: chronotypeIsLearning ? 0 : 1, need: 1, unit: "nights",
                         isExample: example, readyOverride: example ? nil : !chronotypeIsLearning),
            LearningItem(title: "Best sleep times", have: min(best.nightsUsed, best.nightsNeeded), need: best.nightsNeeded,
                         unit: "school nights", isExample: example),
            // Her own logged nights even while the rest is example data.
            LearningItem(title: "Caffeine and your sleep", have: min(caffeine.nightsLogged, caffeine.target),
                         need: caffeine.target, unit: "nights"),
        ]
    }
}

/// "Learning you": one page with every learning counter in the app, what's
/// ready and what unlocks next (D-L1). Reached from the Sleep tab.
struct LearningView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let items = model.learningItems
        let ready = items.filter(\.isReady).count
        Screen(title: "Learning you", accent: .purple) {
            SampleDataBanner()
            SummaryHeader(eyebrow: "Learning you",
                          value: model.usingSampleData ? "Example" : "\(ready) of \(items.count)",
                          unit: model.usingSampleData ? nil : "ready",
                          line: line(items),
                          accent: .purple,
                          info: Explanation(id: "learning-you", title: "Learning you",
                                            meaning: "Most numbers in the app start from typical values and switch to your own once your Watch has recorded enough nights and you've checked in enough mornings.",
                                            forYou: "Wearing your Watch to bed and doing the morning check-in is what moves these along. Nothing here needs setting up."))
            RowCard {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { RowDivider() }
                    LearningRow(item: item)
                }
            }
            RowCard {
                let found = model.patternFactors.filter { $0.sentence != nil }.count
                MetricRow(title: "Patterns", note: found == 0 ? "Nothing clear yet" : "\(found) found in your nights",
                          systemImage: "sparkle.magnifyingglass", accent: .indigo) { PatternsView() }
            }
        }
    }

    /// What unlocks next, in one sentence.
    private func line(_ items: [LearningItem]) -> String {
        if model.usingSampleData {
            return "Example numbers until Apple Health has \(AppModel.nightsNeeded) of your nights. Then each one learns from you."
        }
        guard let next = items.filter({ !$0.isReady }).max(by: { $0.progress < $1.progress }) else {
            return "Everything is learned from your own data now."
        }
        return "Next: \(next.title.prefix(1).lowercased() + next.title.dropFirst()), \(next.status.lowercased())."
    }
}

/// A learning item: a small ring, the name and how far along it is.
private struct LearningRow: View {
    var item: LearningItem
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let p = Palette(scheme: scheme)
        let accent: Accent = item.isReady ? .mint : item.isExample ? .yellow : .purple
        let status = Text(item.status)
            .font(.secondary)
            .fontWeight(.semibold)
            .foregroundStyle(item.isReady ? accent.ink(scheme) : p.secondary)
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: Space.m) {
            ZStack {
                Circle().stroke(accent.track(scheme), lineWidth: 4)
                if item.progress > 0 {
                    Circle().trim(from: 0, to: item.progress)
                        .stroke(accent.fill(scheme), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if item.isReady {
                    Image(systemName: "checkmark")
                        .font(.scaled(size: 11, weight: .bold))
                        .foregroundStyle(accent.ink(scheme))
                }
            }
            .frame(width: 28, height: 28)
            .frame(width: Sizes.icon, height: Sizes.icon)
            .accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(item.title).font(.bodyEmphasis).fixedSize(horizontal: false, vertical: true)
                    status
                }
            } else {
                Text(item.title)
                    .font(.bodyEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                status.multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, minHeight: Sizes.tallRow, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
