import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            greeting
            switch model.healthState {
            case .loading:
                Card { ProgressView("Reading Apple Health…").frame(maxWidth: .infinity) }
            case .failed(let message):
                Card { Note("Couldn’t read Apple Health: \(message)") }
            default:
                lastNightCard
                if let exam = model.upcomingExams.first { examBanner(exam) }
                tiles
            }
        }
        .page()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await model.refreshHealth()
            await model.refreshCalendar()
        }
    }

    private var header: some View {
        HStack {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.muted)
            Spacer()
            Button { showSettings = true } label: {
                Text("A").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44).background(Color.peach, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
        return (Text("Good \(part), Ashley. ") + Text(advice).italic().foregroundColor(.mainText))
            .font(.serifTitle(30)).foregroundStyle(Color.ink).lineSpacing(2)
    }

    private var advice: String {
        let today = Day.key(.now)
        if let exam = model.upcomingExams.first(where: { Day.between(today, $0.date) <= 3 }) {
            let d = Day.between(today, exam.date)
            let when = d == 0 ? "today" : d == 1 ? "tomorrow" : Day.weekdayName(exam.date, long: true)
            return "\(exam.title) is \(when), so protect your sleep before it."
        }
        if let w = model.weekend { return "On school nights you’re usually asleep by \(clockTime(w.schoolNights.bedtime))." }
        return "Here’s what your Watch has been noticing."
    }

    @ViewBuilder private var lastNightCard: some View {
        if let n = model.lastNight {
            Card(fill: .lavender) {
                HStack {
                    CardLabel("Last night")
                    Spacer()
                    Pill(text: Day.short(n.date), fill: .surface, ink: .ink)
                }
                Text(hoursMinutes(Double(n.asleepMinutes))).font(.number(34)).foregroundStyle(Color.ink)
                VStack(spacing: 8) {
                    row("Asleep", clockTime(Double(n.bedtime)))
                    row("Awake", clockTime(Double(n.wake)))
                    row("Resting HR", compare(model.health.restingHr, " bpm"))
                    row("HRV", compare(model.health.hrv, " ms"))
                }
                Note("Resting HR and HRV are this morning’s, against your typical day over the last 4 weeks. Higher resting HR or lower HRV means your body is less recovered.")
            }
        } else {
            Card(fill: .lavender) {
                CardLabel("Last night")
                Note("No sleep in Apple Health yet. Wear your Watch to bed with Sleep Focus on, and your nights show up here the next morning.")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.ink)
            Spacer()
            Text(value).fontWeight(.bold).foregroundStyle(Color.ink)
        }
        .font(.system(size: 15))
    }

    private func compare(_ series: [String: Double], _ unit: String) -> String {
        guard let latest = series.keys.max(), Day.between(latest, Day.key(.now)) <= 1, let value = series[latest] else { return "no data today" }
        let now = "\(Int(value.rounded()))\(unit)"
        guard let typical = model.typical(series) else { return now }
        let diff = Int((value - typical).rounded())
        return diff == 0 ? "\(now), typical" : "\(now) · \(signed(Double(diff), ""))"
    }

    private func examBanner(_ exam: CalendarEvent) -> some View {
        let d = Day.between(Day.key(.now), exam.date)
        return HStack(spacing: 12) {
            Image(systemName: "calendar").font(.system(size: 20)).foregroundStyle(Color.butterInk)
                .frame(width: 40, height: 40).background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
                Text(d == 0 ? "Today" : d == 1 ? "Tomorrow" : "\(Day.weekdayName(exam.date, long: true)), in \(d) days")
                    .font(.system(size: 14)).foregroundStyle(Color.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.butter, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            if let w = model.weekend {
                SmallTile(icon: "arrow.left.and.right", label: "Weekend shift", value: hoursMinutes(Double(abs(w.midpointShift))), fill: .peach, ink: .peachInk)
            }
            if let c = model.lateNight {
                SmallTile(icon: "moon.zzz.fill", label: "2am night costs", value: "−" + hoursMinutes(Double(max(0, c.sleepLost))), fill: .lavender, ink: .mainText)
            }
            SmallTile(icon: "cup.and.saucer.fill", label: "Caffeine logs", value: "\(model.health.caffeine.count)", fill: .butter, ink: .butterInk)
            SmallTile(icon: "bed.double.fill", label: "Nights tracked", value: "\(model.health.nights.count)", fill: .mint, ink: .mintInk)
        }
    }
}

private struct SmallTile: View {
    var icon: String
    var label: String
    var value: String
    var fill: Color
    var ink: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(ink)
                .frame(width: 40, height: 40).background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.muted)
            Text(value).font(.number(26)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(red: 20 / 255, green: 20 / 255, blue: 40 / 255).opacity(0.06), radius: 1, y: 1)
    }
}
