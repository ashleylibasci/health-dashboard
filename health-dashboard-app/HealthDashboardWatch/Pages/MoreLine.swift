import SwiftUI

/// One short line with the rest of the explanation behind a tap (D-W6), so
/// a Watch page never shows a paragraph. The full text opens in a sheet.
struct MoreLine: View {
    let line: String
    let detail: String
    var color: Color = WatchStyle.secondaryText
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            HStack(spacing: 4) {
                Text(line)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "info.circle")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityLabel(line)
        .accessibilityHint("Shows more")
        .sheet(isPresented: $open) {
            ScrollView {
                Text(detail)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
