import SwiftUI

/// The app's four tabs.
enum AppTab: Hashable {
    case today, sleep, body, log
}

private struct OpenTabKey: EnvironmentKey {
    static let defaultValue: @MainActor (AppTab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Switches to another tab. A link to another tab's main screen uses
    /// this instead of pushing a second copy of it onto this tab's stack.
    var openTab: @MainActor (AppTab) -> Void {
        get { self[OpenTabKey.self] }
        set { self[OpenTabKey.self] = newValue }
    }
}

/// The header at the top of every tab: the date in caps, the screen title,
/// and the Settings avatar on the title row. It scrolls with the page.
struct TabHeader: View {
    var title: String
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    init(_ title: String) { self.title = title }

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(BodyLogStyle.todayLine)
                    .font(.scaled(size: 13, weight: .semibold))
                    .tracking(0.5)
                    .secondaryText()
                Text(title)
                    .font(.screenTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: Space.s)
            SettingsAvatar()
                .padding(.top, Space.s)
        }
        .padding(.top, Space.xs)
    }
}

/// The round button into Settings, with her initial when she gave a name.
/// The same on all four tabs.
struct SettingsAvatar: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    private var initial: String? {
        let name = (store.data.name ?? "").trimmingCharacters(in: .whitespaces)
        return name.first.map { String($0).uppercased() }
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        NavigationLink {
            SettingsView()
        } label: {
            Group {
                if let initial {
                    Text(initial).font(.scaled(size: 17, weight: .bold))
                } else {
                    Image(systemName: "person.fill").font(.scaled(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(Accent.indigo.ink(scheme))
            .frame(width: 40, height: 40)
            .background(p.chip, in: Circle())
            .overlay(Circle().strokeBorder(p.cardBorder))
            .frame(width: Sizes.minTap, height: Sizes.minTap)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Settings and profile")
    }
}

/// A row like `LinkRow` that switches to another tab instead of pushing a
/// screen.
struct TabLinkRow: View {
    var title: String
    var subtitle: String? = nil
    var systemImage: String
    var accent: Accent
    var tab: AppTab
    @Environment(\.openTab) private var openTab
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        Button { openTab(tab) } label: {
            HStack(spacing: Space.m) {
                Image(systemName: systemImage)
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(accent.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).font(.bodyEmphasis)
                    if let subtitle { Text(subtitle).font(.secondary).foregroundStyle(p.secondary) }
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(p.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Sizes.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A heading between groups of cards on a tab: 20pt bold, sentence case,
/// with the section gap above it.
struct SectionHeading<Trailing: View>: View {
    var text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        AdaptiveStack(spacing: Space.xs, alignment: .firstTextBaseline) {
            Text(text).font(.section).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, Space.section - Space.m - Space.s)
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text: text) { EmptyView() }
    }
}
