import SwiftUI
import HealthCore

/// The Health guide's library: Help now pinned first, then every section's
/// articles as rows, searchable. Birth-control articles show only for her
/// method. Pushed from Settings.
struct HealthGuideView: View {
    @EnvironmentObject private var store: DataStore
    @State private var query = ""

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The sections after Help now, each with the articles that apply to her
    /// and match the search; empty ones are left out.
    private var sections: [GuideSection] {
        HealthGuide.sections.dropFirst().compactMap { section in
            var s = section
            s.articles = section.articles(for: store.birthControl).filter { $0.matches(query) }
            return s.articles.isEmpty ? nil : s
        }
    }

    var body: some View {
        let shown = sections
        Screen(title: "Health guide", accent: .indigo) {
            // Help now never hides behind a search.
            GuideSectionList(section: HealthGuide.helpNowSection, showsLinks: true)
            ForEach(shown) { section in
                GuideSectionList(section: section)
            }
            if searching && shown.isEmpty {
                Text("Nothing else matches \u{201C}\(query)\u{201D}.")
                    .font(.bodyText)
                    .secondaryText()
                    .padding(.top, Space.s)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search the guide")
    }
}

/// A section heading and its articles as rows in one card. Help now also
/// shows each article's call and text buttons on the row.
private struct GuideSectionList: View {
    var section: GuideSection
    var showsLinks = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeading(section.title)
            RowCard(accent: showsLinks ? section.accent : nil) {
                ForEach(Array(section.articles.enumerated()), id: \.element.id) { i, article in
                    if i > 0 { RowDivider() }
                    GuideArticleRow(article: article, section: section, showsLinks: showsLinks)
                }
            }
        }
    }
}

/// One article in the library: icon, title and summary, pushing the article.
private struct GuideArticleRow: View {
    var article: GuideArticle
    var section: GuideSection
    var showsLinks: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: Space.s) {
            NavigationLink { GuideArticleView(article: article) } label: {
                HStack(spacing: Space.m) {
                    RowIcon(systemImage: section.systemImage, accent: section.accent)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(article.title).font(.bodyEmphasis)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(article.summary).font(.secondary).foregroundStyle(p.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Space.s)
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(p.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: Sizes.tallRow, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            if showsLinks && !article.links.isEmpty {
                GuideLinkButtons(links: article.links, accent: section.accent)
                    .padding(.leading, Sizes.icon + Space.m)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
    }
}

/// Full-width call and text buttons, side by side (stacked at the largest
/// text sizes).
struct GuideLinkButtons: View {
    var links: [CalloutLink]
    var accent: Accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AdaptiveStack(spacing: Space.s) {
            ForEach(links) { link in
                Link(destination: link.url) {
                    Label(link.title, systemImage: link.systemImage)
                        .font(.bodyEmphasis)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: Sizes.minTap)
                        .foregroundStyle(scheme == .dark ? Color(hex: 0x1A0E00) : .white)
                        .background(scheme == .dark ? accent.fill(.dark) : accent.ink(.light), in: Capsule())
                }
                .accessibilityLabel(link.title)
            }
        }
    }
}

/// One Health guide article, pushed: the summary, its call buttons, the
/// body (paragraphs, bullets, subheadings, a callout) and the source line.
struct GuideArticleView: View {
    var article: GuideArticle
    @Environment(\.colorScheme) private var scheme

    private var accent: Accent { HealthGuide.section(of: article)?.accent ?? .indigo }

    var body: some View {
        let p = Palette(scheme: scheme)
        Screen(title: article.title, accent: accent) {
            Text(article.summary)
                .font(.cardTitle)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)
            if !article.links.isEmpty {
                GuideLinkButtons(links: article.links, accent: accent)
            }
            // "Taking something new?" above the medicines list (H-A9).
            if article.id.hasPrefix("medicines-"), let method = article.methods?.first {
                MedicineCheckField(method: method)
            }
            Card {
                ForEach(Array(article.body.enumerated()), id: \.offset) { _, block in
                    blockView(block, p)
                }
            }
            if let source = article.source {
                Text(source)
                    .font(.secondary)
                    .foregroundStyle(p.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: GuideArticle.Block, _ p: Palette) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.bodyText)
                .lineSpacing(2)
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let text):
            Text(text)
                .font(.cardTitle)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Space.xs)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("\u{2022}").font(.bodyText).foregroundStyle(accent.ink(scheme))
                            .accessibilityHidden(true)
                        Text(item)
                            .font(.bodyText)
                            .foregroundStyle(p.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .callout(let text):
            Text(text)
                .font(.bodyEmphasis)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        }
    }
}

/// One guide section on its own page: its articles as rows. For a
/// `LearnMoreRow` that covers a whole topic.
struct GuideSectionView: View {
    var section: GuideSection
    @EnvironmentObject private var store: DataStore

    var body: some View {
        var shown = section
        shown.articles = section.articles(for: store.birthControl)
        return Screen(title: section.title, accent: section.accent) {
            GuideSectionList(section: shown, showsLinks: section.id == HealthGuide.helpNowSection.id)
        }
    }
}

/// The "Learn more" row at the bottom of a screen: a book icon, the title
/// ("Learn more about sleep": X is 2 to 4 words) and a chevron, in the
/// accent's ink. It pushes one Health guide article, or a whole section.
///
/// One per screen, always last: alone in a `Card(density: .compact)`, or
/// as the footer of the `SummaryHeader` card. Use it instead of a long
/// paragraph or a sideways link to another screen's explanation.
struct LearnMoreRow: View {
    var title: String
    var accent: Accent = .indigo
    private var article: GuideArticle?
    private var section: GuideSection?
    @Environment(\.colorScheme) private var scheme

    /// A row that opens one article: `LearnMoreRow("Learn more about sleep", article: .troubleSleeping)`.
    init(_ title: String, article: GuideArticle, accent: Accent = .indigo) {
        self.title = title
        self.article = article
        self.section = nil
        self.accent = accent
    }

    /// A row that opens a whole section (its articles as a list).
    init(_ title: String, section id: String, accent: Accent = .indigo) {
        self.title = title
        self.article = nil
        self.section = HealthGuide.sections.first { $0.id == id }
        self.accent = accent
    }

    var body: some View {
        NavigationLink {
            if let article {
                GuideArticleView(article: article)
            } else if let section {
                GuideSectionView(section: section)
            } else {
                HealthGuideView()
            }
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "book.closed.fill")
                    .font(.scaled(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.bodyEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Palette(scheme: scheme).tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(accent.ink(scheme))
            .frame(maxWidth: .infinity, minHeight: Sizes.minTap, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Health guide")
    }
}
