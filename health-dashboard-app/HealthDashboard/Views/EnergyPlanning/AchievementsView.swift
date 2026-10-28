import SwiftUI
import HealthCore

/// Streaks and wins: how many streaks are going and the next badge first,
/// then each streak as a row and the badges as a grid. A badge's details
/// open in a sheet, so the page never grows under her finger.
struct AchievementsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var openBadge: AppModel.Badge? = nil
    @State private var openStreak: AppModel.StreakInfo? = nil

    var body: some View {
        let badges = model.badges
        // One title, the nav title, named as everywhere else (Valtonen F8,
        // Dubois 9).
        Screen(title: "Streaks and badges", accent: .yellow) {
            SampleDataBanner()
            summary
            RowCard {
                ForEach(Array(model.streaks.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { RowDivider() }
                    MetricRow(title: s.title, note: "\(s.unit.prefix(1).uppercased() + s.unit.dropFirst()) in a row \u{00B7} longest \(s.longest)", value: "\(s.current)",
                              systemImage: "flame.fill", accent: accent(for: s.title), action: { openStreak = s })
                }
            }
            badgesCard(badges)
        }
        .bottomSheet(item: $openStreak, title: { $0.title }) { s in
            let m = meaning(for: s.title)
            Text("\(s.current) \(s.unit) in a row \u{00B7} longest \(s.longest)").font(.cardTitle)
            Text(m.0).font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Text(m.1).font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bottomSheet(item: $openBadge, title: { $0.title }) { b in
            badgeDetail(b)
        }
    }

    // MARK: Summary

    private var summary: some View {
        let going = model.streaks.filter { $0.current > 0 }.count
        let line = model.nextBadge.map { "Next badge: \($0.title), \($0.progress) of \($0.goal)." }
            ?? "You've earned every badge."
        return SummaryHeader(eyebrow: "Streaks", value: "\(going) of \(model.streaks.count)", unit: "going",
                             line: line, accent: .yellow,
                             info: Explanation(id: "streaks", title: "Streaks",
                                               meaning: "A streak counts days in a row. Until today's night or check-in is in, it runs through yesterday.",
                                               forYou: "Miss a day and it starts again, but your longest stays."))
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
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 2 : 3)
        return Card {
            AdaptiveStack(spacing: 4, alignment: .firstTextBaseline) {
                Text("Badges").font(.cardTitle).accessibilityAddTraits(.isHeader)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("\(earned) of \(badges.count) earned \u{00B7} tap one").font(.secondary).fontWeight(.semibold).secondaryText()
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(badges) { b in
                    BadgeCell(badge: b) { openBadge = b }
                }
            }
        }
    }

    private func badgeDetail(_ b: AppModel.Badge) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(b.earned ? "Earned" : "\(b.progress) of \(b.goal)")
                .font(.cardTitle)
                .foregroundStyle(b.earned ? Accent.mint.ink(scheme) : Palette(scheme: scheme).primary)
            Text(b.howTo).font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            if !b.earned {
                BarRow(label: "Progress", fraction: b.fraction, valueText: "\(Int((b.fraction * 100).rounded()))%", accent: b.accent)
            }
        }
    }
}

// MARK: - Subviews

private struct BadgeCell: View {
    var badge: AppModel.Badge
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
                        Circle().strokeBorder(badge.accent.fill(scheme).opacity(0.45), lineWidth: 1)
                    } else {
                        Circle().fill(p.chip)
                        Circle().strokeBorder(p.tertiary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    Image(systemName: earned ? badge.systemImage : "lock.fill")
                        .font(.section)
                        .foregroundStyle(earned ? badge.accent.ink(scheme) : p.tertiary)
                }
                .frame(width: 60, height: 60)
                // Two lines at most; the full name is in the sheet title.
                Text(badge.title)
                    .font(.secondary).fontWeight(earned ? .bold : .semibold)
                    .foregroundStyle(earned ? p.primary : p.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
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
    }
}
