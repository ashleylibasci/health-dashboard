import Foundation
import HealthCore

/// The Health guide: the app's longer health reading (when to get care,
/// missed pills, insomnia, alcohol poisoning signs…), moved off the main
/// screens so each screen answers "how am I?" first. Opened from Settings
/// (first row) and from the one `LearnMoreRow` at the bottom of a screen.
///
/// Each section's articles live in their own file (`Guide+Sleep.swift`:
/// `extension HealthGuide { static let sleep: [GuideArticle] = [...] }`).
/// Copy that moves here from a screen moves word for word; only the
/// one-line `summary` is new, and it says nothing the body doesn't.
///
/// To add an article: define it as a `static let` on `GuideArticle` in its
/// section's file, list it in that section's array, and link to it with
/// `LearnMoreRow("Learn more about sleep", article: .troubleSleeping)`.
enum HealthGuide {
    /// Every section, in the order the guide lists them. Help now is
    /// always first and never hidden by search.
    static let sections: [GuideSection] = [
        GuideSection(id: "helpNow", title: "Help now", systemImage: "phone.fill", accent: .coral,
                     articles: helpNow),
        GuideSection(id: "sleep", title: "Sleep", systemImage: "moon.zzz.fill", accent: .purple,
                     articles: sleep),
        GuideSection(id: "sickDays", title: "Sick days", systemImage: "cross.case.fill", accent: .coral,
                     articles: sickDays),
        GuideSection(id: "birthControl", title: "Birth control", systemImage: "pills.fill", accent: .indigo,
                     articles: birthControl),
        GuideSection(id: "periods", title: "Periods and cycle care", systemImage: "drop.fill", accent: .pink,
                     articles: periods),
        GuideSection(id: "alcohol", title: "Alcohol", systemImage: "wineglass.fill", accent: .purple,
                     articles: alcohol),
        GuideSection(id: "caffeineWater", title: "Caffeine and water", systemImage: "cup.and.saucer.fill", accent: .yellow,
                     articles: caffeineWater),
        GuideSection(id: "stress", title: "Stress and mood", systemImage: "brain.head.profile", accent: .blue,
                     articles: stress),
        GuideSection(id: "energy", title: "Energy", systemImage: "bolt.fill", accent: .mint,
                     articles: energy),
    ]

    static var helpNowSection: GuideSection { sections[0] }

    /// The section an article is filed under.
    static func section(of article: GuideArticle) -> GuideSection? {
        sections.first { $0.articles.contains { $0.id == article.id } }
    }

    /// Looks an article up by its id (for links stored as strings).
    static func article(id: String) -> GuideArticle? {
        sections.lazy.flatMap(\.articles).first { $0.id == id }
    }
}

/// One group of articles in the Health guide.
struct GuideSection: Identifiable, Hashable {
    var id: String
    var title: String
    var systemImage: String
    var accent: Accent
    var articles: [GuideArticle]

    /// The articles that apply to her (birth-control articles only for
    /// the methods they're about).
    func articles(for method: BirthControl?) -> [GuideArticle] {
        articles.filter { $0.applies(to: method) }
    }
}

/// One Health guide article: a title, a one-line summary for the list,
/// and the body as paragraphs, bullet lists and subheadings, with an
/// optional source line ("From the CDC's 2024 guidance") and call or text
/// buttons (988, 911).
struct GuideArticle: Identifiable, Hashable {
    enum Block: Hashable {
        case paragraph(String)
        case bullets([String])
        /// A subheading inside the article.
        case heading(String)
        /// A tinted box for the line that matters most ("Get care right away if…").
        case callout(String)
    }

    var id: String
    var title: String
    /// One line, shown under the title in the guide's list.
    var summary: String
    var body: [Block]
    /// Where the advice comes from, shown small at the end.
    var source: String? = nil
    /// Extra words search should match ("insomnia", "CBT-I").
    var keywords: [String] = []
    /// Call or text buttons shown under the summary.
    var links: [CalloutLink] = []
    /// The birth-control methods it's about; nil for everyone.
    var methods: Set<BirthControl>? = nil

    func applies(to method: BirthControl?) -> Bool {
        guard let methods else { return true }
        return method.map { methods.contains($0) } ?? false
    }

    /// Whether the article matches a search (title, summary, keywords, body).
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let text = ([title, summary] + keywords + body.flatMap(\.texts)).joined(separator: " ")
        return q.split(separator: " ").allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }
}

extension GuideArticle.Block {
    /// The words in the block, for search.
    var texts: [String] {
        switch self {
        case .paragraph(let s), .heading(let s), .callout(let s): [s]
        case .bullets(let items): items
        }
    }
}
