import SwiftUI

/// A small ⓘ button that opens a plain-language explanation of a term.
struct InfoButton: View {
    var explanation: Explanation
    @State private var showing = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(Palette(scheme: scheme).tertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .sheet(isPresented: $showing) { ExplanationSheet(explanation: explanation) }
    }

    /// "What is HRV?", but a title that's already a question reads
    /// "Explain: How stressed do you feel?" (not "What is How…??").
    private var spokenLabel: String {
        let title = explanation.title.trimmingCharacters(in: .whitespaces)
        return title.hasSuffix("?") ? "Explain: \(title)" : "What is \(title)?"
    }
}

extension InfoButton {
    init(topic: Topic) { self.init(explanation: topic.explanation) }
    /// A one-off explanation for something that has no shared `Topic`.
    init(title: String, meaning: String, forYou: String, howWeGotIt: String? = nil) {
        self.init(explanation: Explanation(id: title, title: title, meaning: meaning, forYou: forYou, howWeGotIt: howWeGotIt))
    }
}

/// A title with an ⓘ next to it.
struct ExplainedTitle: View {
    var text: String
    var explanation: Explanation
    var size: CGFloat = 15
    init(text: String, topic: Topic, size: CGFloat = 15) { self.text = text; self.explanation = topic.explanation; self.size = size }
    init(text: String, explanation: Explanation, size: CGFloat = 15) { self.text = text; self.explanation = explanation; self.size = size }
    var body: some View {
        HStack(spacing: 0) {
            Text(text).font(.scaled(size: size, weight: .bold))
            InfoButton(explanation: explanation).padding(.vertical, -12)
        }
    }
}

/// "How we got this number" link that opens the method behind a number.
struct HowWeGotThisLink: View {
    var explanation: Explanation
    var label = "Learn how we got this number"
    @State private var showing = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                Text(label)
            }
            .font(.scaled(size: 14, weight: .semibold))
            .foregroundStyle(Accent.indigo.ink(scheme))
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { ExplanationSheet(explanation: explanation, method: true) }
    }
}

extension HowWeGotThisLink {
    init(topic: Topic, label: String = "Learn how we got this number") { self.init(explanation: topic.explanation, label: label) }
    /// The method behind one screen's number, kept off the main page.
    init(title: String, method: String, meaning: String = "", label: String = "Learn how we got this number") {
        self.init(explanation: Explanation(id: title, title: title, meaning: meaning, forYou: "", howWeGotIt: method), label: label)
    }
}

struct ExplanationSheet: View {
    var explanation: Explanation
    var method = false
    init(topic: Topic, method: Bool = false) { self.explanation = topic.explanation; self.method = method }
    init(explanation: Explanation, method: Bool = false) { self.explanation = explanation; self.method = method }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let e = explanation
        let p = Palette(scheme: scheme)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if method, let how = e.howWeGotIt {
                        section("How we got this number", how)
                        if !e.meaning.isEmpty { section("What it means", e.meaning) }
                    } else {
                        if !e.meaning.isEmpty { section("What it means", e.meaning) }
                        if !e.forYou.isEmpty { section("What it means for you", e.forYou) }
                        if let how = e.howWeGotIt {
                            DisclosureGroup("How we got this number") {
                                Text(how).font(.scaled(size: 15)).foregroundStyle(p.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            }
                            .font(.scaled(size: 15, weight: .semibold))
                            .tint(Accent.indigo.ink(scheme))
                        }
                    }
                }
                .padding(20)
            }
            .background(p.background)
            .navigationTitle(e.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            Text(body).font(.scaled(size: 16)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The bubble that follows your finger on interactive charts.
struct ChartReadout: View {
    var title: String
    var value: String
    var detail: String? = nil
    var accent: Accent = .indigo
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(p.secondary)
            Text(value).font(.scaledNumber(18)).foregroundStyle(accent.ink(scheme))
            if let detail { Text(detail).font(.scaled(size: 12)).foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(scheme == .dark ? Color(hex: 0x1C1E30) : .white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.cardBorder))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .frame(maxWidth: 220, alignment: .leading)
    }
}

/// Default hint under interactive charts.
struct ScrubHint: View {
    var text = "Tap or slide along the chart to see details"
    var body: some View {
        Label(text, systemImage: "hand.point.up.left").font(.scaled(size: 12)).secondaryText()
    }
}
