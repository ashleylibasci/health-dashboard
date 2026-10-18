import SwiftUI

struct SleepView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sleep").font(.serifTitle(34)).foregroundStyle(Color.ink)
            let week = model.lastWeek
            if week.isEmpty {
                Card { Note("No sleep in Apple Health yet.") }
            } else {
                HStack(spacing: 10) {
                    Tile(label: "Average", value: hoursMinutes(mean(week.map { Double($0.asleepMinutes) })!), fill: .lavender, ink: .mainText)
                    Tile(label: "Asleep at", value: clockTime(median(week.map { Double($0.bedtime) })!), fill: .lavender, ink: .mainText)
                    Tile(label: "Nights", value: "\(week.count)", fill: .mint, ink: .mintInk)
                }
                Card {
                    CardLabel("When you slept · last \(week.count) nights", color: .muted)
                    WeekChart(nights: week)
                    HStack(spacing: 6) {
                        Circle().fill(Color.main).frame(width: 10, height: 10)
                        Text("School nights")
                        Circle().fill(Color.peachBar).frame(width: 10, height: 10).padding(.leading, 6)
                        Text("Fri & Sat")
                    }
                    .font(.system(size: 13)).foregroundStyle(Color.muted)
                }
            }
            weekendCard
        }
        .page()
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private var weekendCard: some View {
        if let w = model.weekend {
            let shift = abs(w.midpointShift)
            Card(fill: .peach) {
                CardLabel("Weekend shift", color: .peachInk)
                Text("\(hoursMinutes(Double(shift))) \(w.midpointShift >= 0 ? "later" : "earlier")").font(.number(30)).foregroundStyle(Color.ink)
                Text(shift < 60 ? "Your body clock barely moves on weekends. That’s ideal."
                     : shift < 120 ? "A small weekend shift. Monday mornings may feel a little harder."
                     : "Like flying a time zone or two every weekend. That’s why Monday mornings feel early.")
                    .font(.system(size: 15)).foregroundStyle(Color.ink)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        Text("School").fontWeight(.bold).foregroundStyle(Color.muted)
                        Text("Weekend").fontWeight(.bold).foregroundStyle(Color.muted)
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    patternRow("Asleep", clockTime(w.schoolNights.bedtime), clockTime(w.weekendNights.bedtime))
                    Divider().gridCellUnsizedAxes(.horizontal)
                    patternRow("Awake", clockTime(w.schoolNights.wake), clockTime(w.weekendNights.wake))
                    Divider().gridCellUnsizedAxes(.horizontal)
                    patternRow("Sleep", hoursMinutes(w.schoolNights.asleepMinutes), hoursMinutes(w.weekendNights.asleepMinutes))
                }
                .font(.system(size: 14))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Note("Your typical night over the last \(w.weeks) weeks · \(w.schoolNights.nights) school nights, \(w.weekendNights.nights) weekend nights. Sleep researchers call this shift “social jetlag.”")
            }
        } else if !model.health.nights.isEmpty {
            Card(fill: .peach) {
                CardLabel("Weekend shift", color: .peachInk)
                Note("Needs at least 4 school nights and 4 weekend nights in the last 8 weeks.")
            }
        }
    }

    private func patternRow(_ label: String, _ school: String, _ weekend: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Color.ink)
            Text(school).fontWeight(.bold).foregroundStyle(Color.ink)
            Text(weekend).fontWeight(.bold).foregroundStyle(Color.ink)
        }
    }
}

/// One bar per night from bedtime to wake, on an 8pm–12pm axis.
struct WeekChart: View {
    var nights: [Night]
    private let start = 2.0 * 60, span = 16.0 * 60

    var body: some View {
        VStack(spacing: 8) {
            ForEach(nights, id: \.date) { n in
                HStack(spacing: 8) {
                    Text(Day.weekdayName(n.date)).font(.system(size: 12)).foregroundStyle(Color.muted).frame(width: 30, alignment: .leading)
                    GeometryReader { geo in
                        let left = fraction(n.bedtime), right = fraction(n.wake)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.track)
                            Capsule().fill(n.isWeekend ? Color.peachBar : Color.main)
                                .frame(width: max(4, (right - left) * geo.size.width))
                                .offset(x: left * geo.size.width)
                        }
                    }
                    .frame(height: 14)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Day.weekdayName(n.date, long: true)): asleep \(clockTime(Double(n.bedtime))), awake \(clockTime(Double(n.wake)))")
            }
            HStack {
                ForEach(["8pm", "12am", "4am", "8am", "12pm"], id: \.self) { t in
                    Text(t)
                    if t != "12pm" { Spacer() }
                }
            }
            .font(.system(size: 12)).foregroundStyle(Color.muted)
            .padding(.leading, 38)
            .accessibilityHidden(true)
        }
    }

    private func fraction(_ minutes: Int) -> CGFloat {
        CGFloat(min(1, max(0, (Double(minutes) - start) / span)))
    }
}
