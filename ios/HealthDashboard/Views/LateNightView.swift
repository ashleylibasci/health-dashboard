import SwiftUI

struct LateNightView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            (Text("What a ") + Text("2am night").italic().foregroundColor(.mainText) + Text(" costs you"))
                .serifTitleFont(34).foregroundStyle(Color.ink)
            if let c = model.lateNight {
                Note("\(c.lateNights) late nights in the last \(c.days) days, compared with your \(c.normalNights) normal nights.")
                AdaptiveStack(spacing: 10) {
                    Tile(label: "That night", value: "−" + hoursMinutes(Double(max(0, c.sleepLost))), caption: "sleep", fill: .peach, ink: .peachInk)
                    Tile(label: "Next day", value: signed(c.nextDay.restingHr, " bpm"), caption: "HRV " + signed(c.nextDay.hrv, " ms"), fill: .peach, ink: .peachInk)
                    Tile(label: "Day after", value: signed(c.dayAfter.restingHr, " bpm"), caption: "HRV " + signed(c.dayAfter.hrv, " ms"), fill: .butter, ink: .butterInk)
                }
                Note("Higher resting heart rate and lower HRV (heart rate variability, the small changes in time between heartbeats) both mean your body is less recovered.")
                if !model.recentLate.isEmpty {
                    Card {
                        CardLabel("Recent late nights", color: .muted)
                        ForEach(Array(model.recentLate.enumerated()), id: \.element.date) { i, n in
                            if i > 0 { Divider() }
                            AdaptiveStack(spacing: 6) {
                                Text("\(Day.short(n.date)) · \(clockTime(Double(n.bedtime)))").scaledFont(15).foregroundStyle(Color.ink)
                                Spacer(minLength: 0)
                                if model.exams.contains(where: { (1...2).contains(Day.between(n.date, $0.date)) }) {
                                    Pill(text: "Before exam", fill: .lavender, ink: .mainText)
                                } else if n.isWeekend {
                                    Pill(text: "Weekend", fill: .peach, ink: .peachInk)
                                } else {
                                    Pill(text: "School night", fill: .lavender, ink: .mainText)
                                }
                            }
                        }
                    }
                }
            } else {
                Card { Note("Needs at least 3 nights asleep after 2am in the last 6 months.") }
            }
        }
        .detailPage()
    }

    private var caffeineCard: some View {
        Card(fill: .butter) {
            CardLabel("Caffeine", color: .butterInk)
            if let last = model.health.caffeine.last {
                Text("\(model.health.caffeine.count) logs").numberFont(30).foregroundStyle(Color.ink)
                Text("Latest on \(Day.short(last)). The caffeine cutoff test needs 2–3 weeks of logs to compare your latest coffee with that night’s sleep.")
                    .scaledFont(15).foregroundStyle(Color.ink)
            } else {
                Text("No caffeine logs yet. Tap the Latte shortcut on your Watch (130 mg each) to start the caffeine cutoff test.")
                    .scaledFont(15).foregroundStyle(Color.ink)
            }
        }
    }
}
