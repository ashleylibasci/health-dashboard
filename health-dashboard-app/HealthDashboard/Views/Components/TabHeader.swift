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
/// and the Health guide and Settings buttons on the title row. It scrolls
/// with the page.
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
            HStack(spacing: 0) {
                GuideButton()
                SettingsAvatar()
            }
            .padding(.top, Space.s)
        }
        .padding(.top, Space.xs)
    }
}

/// The Health guide's front door (D-S3): a book beside the Settings
/// button on every tab, since a library isn't a setting.
struct GuideButton: View {
    var body: some View {
        NavigationLink {
            HealthGuideView()
        } label: {
            Image(systemName: "book.closed.fill")
                .font(HeaderCircle.iconFont(16))
                .modifier(HeaderCircle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Health guide")
    }
}

/// The 40pt chip circle behind the tab header's buttons, in a 44pt target.
private struct HeaderCircle: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    /// Scaled with the text size, but never past what fits the circle.
    static func iconFont(_ size: CGFloat) -> Font {
        .system(size: min(Font.scaledSize(size), 22), weight: .semibold)
    }

    func body(content: Content) -> some View {
        let p = Palette(scheme: scheme)
        content
            .foregroundStyle(Accent.indigo.ink(scheme))
            .frame(width: 40, height: 40)
            .background(p.chip, in: Circle())
            .overlay(Circle().strokeBorder(p.cardBorder))
            .frame(width: Sizes.minTap, height: Sizes.minTap)
            .contentShape(Circle())
    }
}

/// The round button into Settings: her initials when she gave a name,
/// otherwise a gear, so it reads as Settings (F9). The same on all four tabs.
struct SettingsAvatar: View {
    @EnvironmentObject var store: DataStore

    /// "AL" for "Ashley Libasci", "A" for "Ashley"; nil without a name.
    static func initials(_ name: String?) -> String? {
        let words = (name ?? "").split(whereSeparator: \.isWhitespace)
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    var body: some View {
        NavigationLink {
            SettingsView()
        } label: {
            Group {
                if let initials = Self.initials(store.data.name) {
                    Text(initials).font(.scaled(size: initials.count > 1 ? 15 : 17, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                } else {
                    Image(systemName: "gearshape.fill").font(HeaderCircle.iconFont(17))
                }
            }
            .modifier(HeaderCircle())
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
