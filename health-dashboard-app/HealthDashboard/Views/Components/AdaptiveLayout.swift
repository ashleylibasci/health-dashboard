import SwiftUI

// Layout pieces for the largest text sizes (Settings › Accessibility ›
// Larger Text). Side-by-side rows stack, segmented controls become a list
// of big buttons, and rows of chips wrap instead of scrolling sideways.

/// A label with its control (picker, time, value) to the right, or the
/// label above the control at accessibility text sizes, so neither gets
/// squeezed into a few letters per line.
struct LabeledControlRow<Label: View, Control: View>: View {
    var spacing: CGFloat = 12
    var alignment: VerticalAlignment = .center
    @ViewBuilder var label: Label
    @ViewBuilder var control: Control
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                label.frame(maxWidth: .infinity, alignment: .leading)
                control
            }
        } else {
            HStack(alignment: alignment, spacing: spacing) {
                label
                Spacer(minLength: 8)
                control
            }
        }
    }
}

/// An `HStack` that becomes a leading-aligned `VStack` at accessibility
/// text sizes.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 12
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            HStack(alignment: alignment, spacing: spacing) { content }
        }
    }
}

/// A segmented control that becomes a stack of full-width, 44pt-or-taller
/// buttons at accessibility text sizes (the system segmented control
/// doesn't grow with the text).
struct AdaptiveSegmentedPicker<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var options: [Value]
    var accent: Accent = .indigo
    var label: (Value) -> String
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, selection: Binding<Value>, options: [Value], accent: Accent = .indigo,
         label: @escaping (Value) -> String) {
        self.title = title
        self._selection = selection
        self.options = options
        self.accent = accent
        self.label = label
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Chip(title: label(option), selected: selection == option, accent: accent) {
                        selection = option
                    }
                    .accessibilityHint(title)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } else {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Lays children out left to right and wraps onto new lines, like words.
/// Used for rows of chips that would otherwise scroll sideways and hide
/// options at large text sizes.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Item { let index: Int; let size: CGSize }
    private struct Row { var items: [Item] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty && needed > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(Item(index: index, size: size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

extension Font {
    /// Big screen headings grow with the text size but stop at 1.6×, so a
    /// long word like "conditions?" still fits on one line at the largest
    /// sizes instead of leaving a lone "?" (body text keeps the 2.2× cap).
    static func headingScaled(size: CGFloat) -> Font {
        .system(size: min(scaledSize(size), size * 1.6), weight: .bold)
    }

    /// Chart axis and marker text (designed at 10–12pt). It follows the text
    /// size through SwiftUI's environment, unlike `.scaled`, so
    /// `chartAxisTextCapped()` can stop it at xxLarge inside charts.
    static func chartLabel(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size <= 11 ? .caption2 : .caption, design: .default, weight: weight)
    }
}

extension View {
    /// Short values (a time, a number, "Not set") stay on one line and
    /// shrink a little instead of breaking into "8:2 / 5".
    func keepsOnOneLine(minimumScale: CGFloat = 0.5) -> some View {
        lineLimit(1).minimumScaleFactor(minimumScale)
    }

    /// A compact time picker reads as one element: "Bedtime, 12:30 AM"
    /// instead of "Time Picker".
    func timePickerAccessibility(_ label: String, time: Date) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityValue(time.formatted(date: .omitted, time: .shortened))
    }
}
