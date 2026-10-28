import SwiftUI
import HealthCore

/// Streaks and wins: current and longest streaks, plus badges worked out
/// from what she already tracks. Locked badges say what earns them.
struct AchievementsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var selectedBadge: String? = nil

    var body: some View {
        let badges = model.badges
        // One title, the nav title, named as everywhere else (Valtonen F8,
        // Dubois 9).
        Screen(title: "Streaks and badges", accent: .yellow) {
            SampleDataBanner()
            streaksCard
            badgesCard(badges)
            if let next = model.nextBadge {
                nextCard(next)
            }
        }
    }

    // MARK: Streaks

    private var streaksCard: some View {
        Card {
            SectionLabel(text: "Your streaks")
            ForEach(model.streaks) { s in
                StreakRow(streak: s, accent: accent(for: s.title), meaning: meaning(for: s.title))
            }
            Text("A streak counts days in a row. Until today's night or check-in is in, it runs through yesterday. Miss a day and it starts again, but your longest stays.")
                .font(.secondary).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func accent(for title: String) -> Accent {
        switch title {
        case "In bed on time": return .purple
        case "Met your sleep need": return .indigo
        default: return .mint
        }
    }

    private func meaning(for title: String) -> (String, String) {
        switch title {
        case "In bed on time":
            return ("Nights you fell asleep within 20 minutes of your planned \(Clock.format(store.data.bedtime)) bedtime.",
                    "A steady bedtime keeps your body clock on time, which makes mornings easier.")
        case "Met your sleep need":
            return ("Nights you slept at least your sleep need (\(Clock.duration(model.sleepNeed.minutes))), give or take 15 minutes.",
                    "Every night that covers your need keeps sleep debt from building up.")
        default:
            return ("Days you did the morning check-in.",
                    "Check-ins teach the app how you actually feel, so its guesses get closer.")
        }
    }

    // MARK: Badges

    private func badgesCard(_ badges: [AppModel.Badge]) -> some View {
        let earned = badges.filter(\.earned).count
        let selected = badges.first { $0.id == selectedBadge }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 2 : 3)
        return Card {
            AdaptiveStack(spacing: 4) {
                SectionLabel(text: "Badges")
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("\(earned) of \(badges.count) earned").font(.secondary).fontWeight(.semibold).secondaryText()
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(badges) { b in
                    BadgeCell(badge: b, selected: b.id == selectedBadge) {
                        selectedBadge = selectedBadge == b.id ? nil : b.id
                    }
                }
            }
            if let selected {
                badgeDetail(selected)
            } else {
                Text("Tap a badge to see what earns it.").font(.secondary).secondaryText()
            }
        }
    }

    private func badgeDetail(_ b: AppModel.Badge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack(spacing: 4) {
                Text(b.title).font(.bodyEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text(b.earned ? "Earned" : "\(b.progress) / \(b.goal)")
                    .font(.secondary).fontWeight(.bold)
                    .foregroundStyle(b.earned ? Accent.mint.ink(scheme) : Palette(scheme: scheme).secondary)
            }
            Text(b.howTo).font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            if !b.earned {
                BarRow(label: "Progress", fraction: b.fraction, valueText: "\(Int((b.fraction * 100).rounded()))%", accent: b.accent)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(b.accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(b.title), \(b.earned ? "earned" : "\(b.progress) of \(b.goal)"). \(b.howTo)")
    }

    private func nextCard(_ b: AppModel.Badge) -> some View {
        Card(accent: .yellow) {
            SectionLabel(text: "Next up", accent: .yellow)
            AdaptiveStack(spacing: 4, alignment: .firstTextBaseline) {
                Text(b.title).font(.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("\(b.progress) / \(b.goal)").font(.numberM).foregroundStyle(Accent.yellow.ink(scheme))
                    .keepsOnOneLine()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(b.title), \(b.progress) of \(b.goal)")
            BarRow(label: "Progress", fraction: b.fraction, valueText: "\(Int((b.fraction * 100).rounded()))%", accent: .yellow)
            Text(b.howTo).font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Subviews

private struct StreakRow: View {
    var streak: AppModel.StreakInfo
    var accent: Accent
    var meaning: (String, String)
    @Environment(\.colorScheme) private var scheme
    @State private var explaining = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text("\(streak.current)").font(.numberL).foregroundStyle(accent.ink(scheme))
                    .keepsOnOneLine()
                Image(systemName: "flame.fill").font(.small).foregroundStyle(accent.ink(scheme))
                    .accessibilityHidden(true)
            }
            .frame(width: 56, height: 56)
            .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(streak.title).font(.bodyEmphasis)
                    InfoButton(title: streak.title, meaning: meaning.0, forYou: meaning.1).padding(.vertical, -12)
                        .accessibilityHidden(true)
                }
                Text("\(streak.current) \(streak.unit) in a row · longest \(streak.longest)")
                    .font(.secondary).secondaryText()
            }
            Spacer(minLength: 0)
        }
        // One stop per streak; its explanation is an action (Ortiz F9).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak.title), \(streak.current) \(streak.unit) in a row, longest \(streak.longest)")
        .accessibilityAction(named: "Explain") { explaining = true }
        .sheet(isPresented: $explaining) {
            ExplanationSheet(explanation: Explanation(id: streak.title, title: streak.title, meaning: meaning.0, forYou: meaning.1))
        }
    }
}

private struct BadgeCell: View {
    var badge: AppModel.Badge
    var selected: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        let earned = badge.earned
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if earned {
                        Circle().fill(badge.accent.tint(scheme))
                        Circle().strokeBorder(badge.accent.fill(scheme).opacity(0.45), lineWidth: selected ? 3 : 1)
                    } else {
                        Circle().fill(p.chip)
                        Circle().strokeBorder(p.tertiary.opacity(0.5), style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: [4, 3]))
                    }
                    Image(systemName: earned ? badge.systemImage : "lock.fill")
                        .font(.section)
                        .foregroundStyle(earned ? badge.accent.ink(scheme) : p.tertiary)
                }
                .frame(width: 60, height: 60)
                Text(badge.title)
                    .font(.secondary).fontWeight(earned ? .bold : .semibold)
                    .foregroundStyle(earned ? p.primary : p.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !earned {
                    Text("\(badge.progress) / \(badge.goal)").font(.small).foregroundStyle(p.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            // Locked badges are told apart by the lock and dashed ring, not
            // by fading: faded text fell to about 3:1 on the light card.
            // Full-strength secondary text is 8:1 (light) and 4.5:1+ (dark).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(earned ? "\(badge.title), earned" : "\(badge.title), locked, \(badge.progress) of \(badge.goal)")
        .accessibilityHint(badge.howTo)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
