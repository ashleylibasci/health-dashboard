import SwiftUI

// D-M5: while she scrolls a detail screen, the answer in its
// `SummaryHeader` ("7h 21m") joins the title in the navigation bar
// ("Sleep · 7h 21m") once the header has scrolled under the bar, and
// leaves again when it comes back. `Screen` owns the bar; the header only
// says whether it's out of sight (a geometry check that fires on the
// change, not every frame).

/// Handed down by a titled `Screen` to its `SummaryHeader`.
struct AnswerPin {
    /// The bottom of the navigation bar, in global coordinates.
    var line: CGFloat
    var set: (String?) -> Void
}

private struct AnswerPinKey: EnvironmentKey {
    static let defaultValue: AnswerPin? = nil
}

extension EnvironmentValues {
    var answerPin: AnswerPin? {
        get { self[AnswerPinKey.self] }
        set { self[AnswerPinKey.self] = newValue }
    }
}

extension View {
    /// Pins `answer` beside the screen's title while this view is scrolled
    /// up under the navigation bar.
    func pinsAnswer(_ answer: String) -> some View { modifier(PinsAnswer(answer: answer)) }
}

private struct PinsAnswer: ViewModifier {
    var answer: String
    @Environment(\.answerPin) private var pin
    @State private var hidden = false

    func body(content: Content) -> some View {
        if let pin {
            let line = pin.line
            content
                .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY < line } action: { under in
                    hidden = under
                    pin.set(under ? answer : nil)
                }
                .onChange(of: answer) { _, new in
                    // A new value (another day or range) while it's pinned.
                    if hidden { pin.set(new) }
                }
        } else {
            content
        }
    }
}

/// The navigation bar's title, with the pinned answer after a dot.
struct PinnedTitle: View {
    var title: String
    var answer: String?
    var accent: Accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.xs) {
            // The title keeps its room while the answer slides in beside it.
            Text(title).layoutPriority(1)
            if let answer {
                Group {
                    Text("\u{00B7}").foregroundStyle(Palette(scheme: scheme).tertiary)
                    Text(answer).foregroundStyle(accent.ink(scheme)).monospacedDigit()
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .font(.headline)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .clipped()
        .animation(Motion.reveal.animation(reduceMotion: reduceMotion), value: answer)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
