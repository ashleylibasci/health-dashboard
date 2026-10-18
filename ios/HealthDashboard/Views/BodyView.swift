import SwiftUI

/// The Body tab: every deep-dive screen in one place.
struct BodyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Body").font(.serifTitle(34)).foregroundStyle(Color.ink).padding(.top, 8)
            link(RecoveryView(), "heart.fill", "Recovery", model.recoveryToday.map { "\($0.score) today · \($0.label)" } ?? "Fills in over your first 14 days")
            link(StressView(), "face.smiling", "Stress", model.stress.map { "\($0.label) right now · \($0.weekLabel.lowercased()) this week" } ?? "From your heart rate during the day", .peach, .peachInk)
            link(EnergyView(), "battery.75percent", "Energy and effort", "Energy left, load, steps, sleep debt, water", .mint, .mintInk)
            link(FitnessView(), "bolt.fill", "Fitness age", model.fitness.map { "Fitness age \($0.fitnessAge) · VO₂ max \(String(format: "%.1f", $0.latest))" } ?? "Needs a VO₂ max reading from your Watch", .mint, .mintInk)
            link(CaffeineView(), "cup.and.saucer.fill", "Caffeine", "Today’s caffeine and your cutoff test", .butter, .butterInk)
            if model.profile?.prefs.drinksTracking ?? true {
                link(DrinksView(), "wineglass.fill", "Drinks and your body", "What the morning after looks like in your data", Color(hex: 0xF3E9FF), Color(hex: 0x7A3FC2))
            }
            link(LateNightView(), "moon.zzz.fill", "Late-night cost", "What a 2am night costs you")
            link(ExamsView(), "calendar", "Exams", model.upcomingExams.first.map { "Next: \($0.title)" } ?? "From your Google Calendar", .butter, .butterInk)
            if model.profile?.tracksCycle ?? false {
                link(CycleView(), "circle.dashed", "Cycle", model.cycle.map { "Day \($0.day) · \($0.phase.rawValue)" } ?? model.pack.map { "Pack day \($0.day)" } ?? "Your cycle and how it affects you", Color(hex: 0xFFE6E2), .peachInk)
            }
            if model.profile?.prefs.showCalories ?? false {
                link(CaloriesView(), "flame.fill", "Calories burned", "Resting and active", Color(hex: 0xFFF1EA), .peachInk)
            }
            if model.profile?.prefs.streaks ?? false {
                link(StreaksView(), "star.fill", "Streaks and wins", "Small goals and badges", .butter, .butterInk)
            }
        }
        .page()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func link<V: View>(_ destination: V, _ icon: String, _ title: String, _ detail: String, _ fill: Color = .lavender, _ ink: Color = .mainText) -> some View {
        NavigationLink { destination } label: { LinkCard(icon: icon, title: title, detail: detail, iconFill: fill, iconInk: ink) }
            .buttonStyle(.plain)
    }
}
