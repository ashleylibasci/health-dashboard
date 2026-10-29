import SwiftUI
import WatchKit

/// Mood from the wrist (F2): the iPhone's mood, anxiety and irritability
/// dots (B1) on the Log page, one tap each. Tapping the chosen dot again
/// takes it back. The phone saves them; until it says so, the tap shows
/// from here. Hidden with phone builds that can't take them.
struct WatchMoodSection: View {
    @EnvironmentObject private var sync: WatchSync
    /// Taps sent from here, by scale, until the phone's snapshot has them.
    @State private var pending: [String: (id: UUID, value: Int)] = [:]
    /// Scales undone here, until the phone's snapshot drops them.
    @State private var cleared: Set<String> = []

    private static let scales: [(key: String, title: String, low: String, high: String)] = [
        ("mood", "Mood", "Very low", "Very good"),
        ("anxiety", "Anxiety", "None", "A lot"),
        ("irritability", "Irritability", "None", "A lot"),
    ]

    var body: some View {
        // `-demo` shows them without a phone build that sends them.
        if let phone = sync.snapshot.moodToday ?? (WatchHealth.demo ? [:] : nil) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How are you today?")
                    .font(WatchStyle.label)
                    .foregroundStyle(WatchStyle.secondaryText)
                ForEach(Self.scales, id: \.key) { scale in
                    row(scale, value: shown(scale.key, phone: phone))
                }
            }
            .padding(.top, 4)
            .onChange(of: phone) { _, new in
                pending = pending.filter { new[$0.key] != $0.value.value }
                cleared = cleared.filter { new[$0] != nil }
            }
        }
    }

    private func shown(_ key: String, phone: [String: Int]) -> Int? {
        if let p = pending[key] { return p.value }
        return cleared.contains(key) ? nil : phone[key]
    }

    private func row(_ scale: (key: String, title: String, low: String, high: String), value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(scale.title).font(.footnote.weight(.semibold))
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { n in
                    let on = value == n
                    Button { tap(scale.key, n, on: on) } label: {
                        Circle()
                            .fill(on ? color(scale.key, n) : WatchStyle.surface)
                            .overlay(Text("\(n)").font(.caption2.weight(.bold))
                                .foregroundStyle(on ? Color.black : WatchStyle.secondaryText))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                    .buttonStyle(WatchPressStyle())
                    .accessibilityLabel("\(scale.title) \(n) of 5, \(n == 1 ? scale.low : n == 5 ? scale.high : "")")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    /// Mint for a good mood or little anxiety, coral the other way.
    private func color(_ key: String, _ n: Int) -> Color {
        let good = key == "mood" ? Double(n - 1) / 4 : Double(5 - n) / 4
        if good >= 0.7 { return Accent.mint.fill(.dark) }
        if good >= 0.4 { return Accent.yellow.fill(.dark) }
        return Accent.coral.fill(.dark)
    }

    @MainActor
    private func tap(_ key: String, _ n: Int, on: Bool) {
        if on, let p = pending[key] {
            // Take back the tap just sent.
            guard sync.send(.undoMood(entryID: p.id)) else { return WKInterfaceDevice.current().play(.failure) }
            pending[key] = nil
            cleared.insert(key)
            WKInterfaceDevice.current().play(.directionDown)
            return
        }
        guard !on else { return }
        let id = UUID()
        guard sync.send(.loggedMood(entryID: id, scale: key, value: n, at: Date())) else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        WKInterfaceDevice.current().play(.click)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            pending[key] = (id, n)
            cleared.remove(key)
        }
    }
}
