import SwiftUI

/// The one line that stays on a main screen while something is urgent or
/// needs her: "No period for 3 months: worth seeing a clinician.",
/// "Google Calendar signed out · Reconnect". A tinted bar with an icon, one
/// line of copy (about 60 characters, at most 2 lines) and a chevron; the
/// whole bar opens the full text (a sheet or a page). Optional round call
/// or text buttons sit at its trailing edge.
///
/// Show it only while its trigger is true (the safety triggers are in the
/// structure review: 4+ drinks, heavy flow, no period for 90 days), at most one per screen, above the
/// `SummaryHeader`. Never use it for tips or anything that's always on.
struct CalloutBar: View {
    var text: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var accent: Accent = .coral
    /// Round buttons after the text ("Call 911").
    var links: [CalloutLink] = []
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let p = Palette(scheme: scheme)
        AdaptiveStack(spacing: Space.s, alignment: .center) {
            Button(action: action) {
                HStack(spacing: Space.m) {
                    Image(systemName: systemImage)
                        .font(.scaled(size: 16, weight: .semibold))
                        .foregroundStyle(accent.ink(scheme))
                        .frame(width: Font.scaledSize(22))
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.bodyEmphasis)
                        .foregroundStyle(p.primary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Space.xs)
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(p.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: Sizes.minTap, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows more")
            if !links.isEmpty {
                HStack(spacing: Space.s) {
                    ForEach(links) { link in CalloutLinkButton(link: link, accent: accent) }
                }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, minHeight: Sizes.tallRow, alignment: .leading)
        .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// A call or text button on a `CalloutBar` or a Health guide article.
struct CalloutLink: Identifiable, Hashable {
    var id: String { title }
    /// "Call 911", spoken by VoiceOver.
    var title: String
    var systemImage: String
    var url: URL

    static func call(_ number: String) -> CalloutLink {
        CalloutLink(title: "Call \(number)", systemImage: "phone.fill", url: URL(string: "tel:\(number)")!)
    }

    static func text(_ number: String) -> CalloutLink {
        CalloutLink(title: "Text \(number)", systemImage: "message.fill", url: URL(string: "sms:\(number)")!)
    }
}

/// A filled 44pt round button that opens a `CalloutLink`.
struct CalloutLinkButton: View {
    var link: CalloutLink
    var accent: Accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Link(destination: link.url) {
            Image(systemName: link.systemImage)
                .font(.scaled(size: 15, weight: .bold))
                .frame(width: Sizes.minTap, height: Sizes.minTap)
                // Light: white on the deep ink; dark: near black on the
                // bright fill.
                .foregroundStyle(scheme == .dark ? Color(hex: 0x1A0E00) : .white)
                .background(scheme == .dark ? accent.fill(.dark) : accent.ink(.light), in: Circle())
        }
        .accessibilityLabel(link.title)
    }
}

// MARK: - Bottom sheet

extension View {
    /// The app's bottom sheet: medium and large detents, a grab bar, a nav
    /// title and Done, on the screen background. For urgent or quick
    /// reading (alcohol poisoning signs, a log form)
    /// where she should swipe down back to where she was. Reference
    /// reading is pushed instead (a Health guide article).
    func bottomSheet<Content: View>(isPresented: Binding<Bool>, title: String,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented) { SheetPage(title: title, content: content) }
    }

    /// `bottomSheet` for an optional item: shown while `item` isn't nil.
    func bottomSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, title: @escaping (Item) -> String,
                                                        @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item) { value in SheetPage(title: title(value)) { content(value) } }
    }
}

/// The body of a `bottomSheet`: a scrolling column with the screen side
/// margins, in its own navigation stack with Done.
struct SheetPage<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xl)
                    .padding(.top, Space.s)
                    .padding(.bottom, Space.scrollEnd)
            }
            .background(p.background)
            .foregroundStyle(p.primary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
