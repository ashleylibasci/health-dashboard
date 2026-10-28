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

    /// "About HRV" (it opens what it is, what to do and how it's worked
    /// out, not only a definition), but a title that's already a question
    /// reads "Explain: How stressed do you feel?".
    private var spokenLabel: String {
        let title = explanation.title.trimmingCharacters(in: .whitespaces)
        return title.hasSuffix("?") ? "Explain: \(title)" : "About \(title)"
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
            Text(text).font(font).tracking(role?.tracking ?? 0)
            InfoButton(explanation: explanation).padding(.vertical, -12)
        }
    }

    /// The type-scale role for the design sizes in use (17 is a card title,
    /// 15 an emphasised line, 22 a headline); other sizes stay bold.
    private var role: TypeRole? {
        switch size {
        case 22: .heading
        case 17: .cardTitle
        case 15: .bodyEmphasis
        default: nil
        }
    }

    private var font: Font { role?.font ?? .scaled(size: size, weight: .bold) }
}

/// "How it's worked out" link that opens the method behind a number.
struct HowWeGotThisLink: View {
    var explanation: Explanation
    var label = HowWeGotThisLink.defaultLabel
    @State private var showing = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle").accessibilityHidden(true)
                Text(label)
            }
            .font(.bodyEmphasis)
            .foregroundStyle(Accent.indigo.ink(scheme))
            .textLinkHitArea()
        }
        .buttonStyle(.plain)
        // The negative padding keeps the 44pt target without the gap; keep
        // the link clear of whatever sits above and below it.
        .padding(.vertical, Space.xs)
        .sheet(isPresented: $showing) { ExplanationSheet(explanation: explanation, method: true) }
    }
}

extension HowWeGotThisLink {
    /// One name for the method link and the sheet section it opens (Dubois 20).
    static let defaultLabel = "How it\u{2019}s worked out"

    init(topic: Topic, label: String = HowWeGotThisLink.defaultLabel) { self.init(explanation: topic.explanation, label: label) }
    /// The method behind one screen's number, kept off the main page.
    init(title: String, method: String, meaning: String = "", label: String = HowWeGotThisLink.defaultLabel) {
        self.init(explanation: Explanation(id: title, title: title, meaning: meaning, forYou: "", howWeGotIt: method), label: label)
    }
}

/// Eating-disorder history is on: explanations leave out "push" and
/// workout advice (Ruiz F13, Cole 5). Set once at the app's root.
private struct HidesEffortTargetsKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var hidesEffortTargets: Bool {
        get { self[HidesEffortTargetsKey.self] }
        set { self[HidesEffortTargetsKey.self] = newValue }
    }
}

extension Explanation {
    /// The same explanation without effort or workout advice, for an
    /// eating-disorder history. Most are unchanged.
    var withoutEffortAdvice: Explanation {
        let forYou: String
        switch id {
        case Topic.recovery.rawValue:
            forYou = "Lower than usual means your body is still catching up (from short sleep, stress, illness or alcohol), so go gently. Higher means you\u{2019}re well rested."
        case Topic.effort.rawValue:
            forYou = "Go by how you feel. Rest is fine on any day."
        case Topic.follicular.rawValue:
            forYou = "Many women notice no difference across their cycle. Go by how you feel."
        default:
            return self
        }
        return Explanation(id: id, title: title, meaning: meaning, forYou: forYou, howWeGotIt: howWeGotIt)
    }
}

struct ExplanationSheet: View {
    var explanation: Explanation
    var method = false
    init(topic: Topic, method: Bool = false) { self.explanation = topic.explanation; self.method = method }
    init(explanation: Explanation, method: Bool = false) { self.explanation = explanation; self.method = method }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.hidesEffortTargets) private var hidesEffortTargets

    var body: some View {
        let e = hidesEffortTargets ? explanation.withoutEffortAdvice : explanation
        let p = Palette(scheme: scheme)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // One set of headings on every sheet (Dubois 20).
                    if method, let how = e.howWeGotIt {
                        section(HowWeGotThisLink.defaultLabel, how)
                        if !e.meaning.isEmpty { section("What it is", e.meaning) }
                    } else {
                        if !e.meaning.isEmpty { section("What it is", e.meaning) }
                        if !e.forYou.isEmpty { section("What to do", e.forYou) }
                        if let how = e.howWeGotIt {
                            DisclosureGroup(HowWeGotThisLink.defaultLabel) {
                                Text(how).font(.bodyText).foregroundStyle(p.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            }
                            .font(.bodyEmphasis)
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
            Text(body).font(.bodyText).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The callout above an interactive chart: what the touched point is
/// (title), its value, and a short note.
///
/// - Full width, so it never changes width while you scrub.
/// - The value is one big tabular number. A value written "72 · Take it
///   steady" shows "72" big and "Take it steady" beside it.
/// - The note always keeps room for three lines, so the chart under it
///   doesn't jump as notes of different lengths come and go (a longer
///   note still shows in full).
/// - Pass `onClear` while something is selected: tapping the readout then
///   clears the selection, back to the summary.
/// - When VoiceOver steps the chart, the new readout is spoken.
struct ChartReadout: View {
    var title: String
    var value: String
    var detail: String? = nil
    var accent: Accent = .indigo
    var onClear: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lines the note always keeps room for.
    private let detailLines = 3

    private var parts: (number: String, qualifier: String?) {
        guard let r = value.range(of: " \u{00B7} ") else { return (value, nil) }
        return (String(value[..<r.lowerBound]), String(value[r.upperBound...]))
    }

    private var spoken: String {
        [title, value, detail].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        let ax = typeSize.isAccessibilitySize
        let shape = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title)
                .font(.secondary).fontWeight(.semibold)
                .foregroundStyle(p.secondary)
                .lineLimit(ax ? nil : 1)
                .minimumScaleFactor(ax ? 1 : 0.8)
            // The qualifier sits under the number at the accessibility
            // sizes instead of wrapping in a narrow column beside it.
            AdaptiveStack(spacing: ax ? 0 : Space.s, alignment: .firstTextBaseline) {
                Text(parts.number)
                    .font(.numberM)
                    .foregroundStyle(accent.ink(scheme))
                    .lineLimit(ax ? nil : 1)
                    .minimumScaleFactor(ax ? 1 : 0.6)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .motion(.select, value: value)
                if let qualifier = parts.qualifier {
                    Text(qualifier)
                        .font(.secondary).fontWeight(.semibold)
                        .foregroundStyle(accent.ink(scheme))
                        .lineLimit(ax ? nil : 1)
                        .minimumScaleFactor(ax ? 1 : 0.8)
                }
            }
            if let detail {
                ZStack(alignment: .topLeading) {
                    if !ax {
                        // Holds the height of three lines.
                        Text(Array(repeating: " ", count: detailLines).joined(separator: "\n"))
                            .font(.secondary)
                            .hidden()
                    }
                    Text(detail)
                        .font(.secondary)
                        .foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scheme == .dark ? Color(hex: 0x1C1E30) : .white, in: shape)
        .overlay(shape.strokeBorder(p.cardBorder))
        .shadow(color: .black.opacity(scheme == .dark ? 0.15 : 0.06), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(onClear == nil ? [] : .isButton)
        .accessibilityHint(onClear == nil ? "" : "Clears the selection")
        .modifier(ClearOnTap(shape: shape, action: onClear))
        .onChange(of: spoken) { _, text in
            if ChartScrubVoiceOver.justStepped {
                AccessibilityNotification.Announcement(text).post()
            }
        }
    }
}

/// Tapping the readout clears the chart's selection, only when the readout
/// was given a way to (otherwise taps pass through untouched).
private struct ClearOnTap: ViewModifier {
    var shape: RoundedRectangle
    var action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(shape)
                .onTapGesture { withMotion(.select) { action() } }
                .accessibilityAction { action() }
        } else {
            content
        }
    }
}

/// Default hint under interactive charts. Hidden from VoiceOver, where
/// the chart itself is adjustable (swipe up or down). One wording
/// everywhere: "Drag across the chart to see each night." (Dubois 30).
struct ScrubHint: View {
    var text = "Drag across the chart to see each point."

    init(text: String = "Drag across the chart to see each point.") { self.text = text }
    /// "Drag across the chart to see each \(unit)."
    init(each unit: String) { self.text = "Drag across the chart to see each \(unit)." }

    var body: some View {
        Label(text, systemImage: "hand.point.up.left")
            .font(.secondary)
            .secondaryText()
            .accessibilityHidden(true)
    }
}
