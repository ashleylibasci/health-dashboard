import SwiftUI
import HealthCore

/// Streaks and wins: current and longest streaks, plus badges worked out
/// from what she already tracks. Locked badges say what earns them.
struct AchievementsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var selectedBadge: String? = nil

    var body: some View {
        let badges = model.badges
        Screen(title: "Streaks and wins", accent: .yellow) {
            Text("Streaks and wins").font(.scaled(size: 30, weight: .bold))
                .accessibilityAddTraits(.isHeader)
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
                .font(.scaled(size: 12)).secondaryText()
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
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return Card {
            HStack {
                SectionLabel(text: "Badges")
                Spacer()
                Text("\(earned) of \(badges.count) earned").font(.scaled(size: 13, weight: .semibold)).secondaryText()
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
                Text("Tap a badge to see what earns it.").font(.scaled(size: 13)).secondaryText()
            }
        }
    }

    private func badgeDetail(_ b: AppModel.Badge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(b.title).font(.scaled(size: 16, weight: .bold))
                Spacer()
                Text(b.earned ? "Earned" : "\(b.progress) / \(b.goal)")
                    .font(.scaled(size: 13, weight: .bold))
                    .foregroundStyle(b.earned ? Accent.mint.ink(scheme) : Palette(scheme: scheme).secondary)
            }
            Text(b.howTo).font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            if !b.earned {
                BarRow(label: "Progress", fraction: b.fraction, valueText: "\(Int((b.fraction * 100).rounded()))%", accent: b.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(b.accent.tint(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func nextCard(_ b: AppModel.Badge) -> some View {
        Card(accent: .yellow) {
            SectionLabel(text: "Next up", accent: .yellow)
            HStack(alignment: .firstTextBaseline) {
                Text(b.title).font(.scaled(size: 18, weight: .bold))
                Spacer()
                Text("\(b.progress) / \(b.goal)").font(.scaledNumber(18)).foregroundStyle(Accent.yellow.ink(scheme))
            }
            BarRow(label: "Progress", fraction: b.fraction, valueText: "\(Int((b.fraction * 100).rounded()))%", accent: .yellow)
            Text(b.howTo).font(.scaled(size: 14)).secondaryText()
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text("\(streak.current)").font(.scaledNumber(26)).foregroundStyle(accent.ink(scheme))
                Image(systemName: "flame.fill").font(.scaled(size: 11)).foregroundStyle(accent.ink(scheme))
                    .accessibilityHidden(true)
            }
            .frame(width: 56, height: 56)
            .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(streak.title).font(.scaled(size: 15, weight: .bold))
                    InfoButton(title: streak.title, meaning: meaning.0, forYou: meaning.1).padding(.vertical, -12)
                }
                Text("\(streak.current) \(streak.unit) in a row · longest \(streak.longest)")
                    .font(.scaled(size: 13)).secondaryText()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
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
                        .font(.scaled(size: 20, weight: .semibold))
                        .foregroundStyle(earned ? badge.accent.ink(scheme) : p.tertiary)
                }
                .frame(width: 60, height: 60)
                Text(badge.title)
                    .font(.scaled(size: 12, weight: earned ? .bold : .semibold))
                    .foregroundStyle(earned ? p.primary : p.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !earned {
                    Text("\(badge.progress) / \(badge.goal)").font(.scaled(size: 11)).foregroundStyle(p.secondary)
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
