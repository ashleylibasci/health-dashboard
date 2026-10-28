import SwiftUI
import HealthCore

/// Energy your body used today, with gentle, non-diet framing: no targets,
/// no food diary, no "earned" or "burn off" language.
struct CaloriesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Screen(title: "Calories", accent: .orange) {
            if model.caloriesHiddenByCondition {
                Card(accent: .indigo) {
                    Text("Calories are hidden").font(.scaled(size: 18, weight: .bold))
                    Text("You added eating-disorder history to your health conditions, so the app keeps calories, step counts, exercise targets and your water goal out of sight everywhere. You can change that in Health conditions.")
                        .font(.scaled(size: 14)).secondaryText().fixedSize(horizontal: false, vertical: true)
                    EatingDisorderSupportRow()
                    LinkRow(title: "Health conditions", systemImage: "heart.text.square.fill", accent: .purple) { ConditionsView() }
                }
            } else {
                SampleDataBanner()
                header
                splitCard
                cycleCard
                framingCard
                Card(density: .compact) {
                    SettingToggleRow(title: "Show calories on Body", detail: "Turn off anytime. No targets, no food diary.",
                                     systemImage: "flame.fill", accent: .orange, isOn: $store.data.showCalories)
                }
                Text("Apple Watch estimates calories from your heart rate and movement. They\u{2019}re often off by 20\u{2013}30% or more, so treat these as estimates, not exact counts.")
                    .font(.scaled(size: 12)).secondaryText().fixedSize(horizontal: false, vertical: true)
                HowWeGotThisLink(title: "Calories",
                                 method: "Resting energy comes from Apple Health's estimate of what your body uses at rest, based on your height, weight, age and sex in the Health app. Make sure Sex is set to Female in Health > Health Details. Active energy comes from your heart rate and movement on your Apple Watch. Both are added up from midnight, and both are estimates that are often off by 20\u{2013}30% or more.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("Energy used today").font(.scaled(size: 15, weight: .semibold)).secondaryText()
                InfoButton(topic: .calories).padding(.vertical, -12)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Int(model.caloriesToday.rounded()).formatted()).font(.scaledNumber(52)).foregroundStyle(Accent.orange.ink(scheme))
                Text("kcal so far").font(.scaled(size: 15, weight: .semibold)).secondaryText()
            }
        }
    }

    private var splitCard: some View {
        let total = max(model.caloriesToday, 1)
        return Card {
            part(title: "Resting", value: model.restingCalories, fraction: model.restingCalories / total, accent: .indigo,
                 meaning: "The energy your body uses just to keep you going: breathing, your heart, your brain, keeping warm. It's most of what you use every day, even on a lazy one.",
                 forYou: "Your brain uses about a fifth of it every day, studying or resting. That\u{2019}s one reason regular meals matter.")
            part(title: "Active", value: model.activeCalories, fraction: model.activeCalories / total, accent: .orange,
                 meaning: "Extra energy from moving: walking to class, stairs, workouts.",
                 forYou: "It goes up and down a lot from day to day. That's normal and nothing to chase.")
        }
    }

    private func part(title: String, value: Double, fraction: Double, accent: Accent, meaning: String, forYou: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(title).font(.scaled(size: 15, weight: .bold))
                InfoButton(title: "\(title) energy", meaning: meaning, forYou: forYou).padding(.vertical, -12)
                Spacer()
                Text("\(Int(value.rounded()).formatted()) kcal").font(.scaledNumber(18))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette(scheme: scheme).track)
                    Capsule().fill(accent.fill(scheme)).frame(width: geo.size.width * max(0, min(fraction, 1)))
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cycleCard: some View {
        if case let .phases(day, _, phase) = model.cycleDisplay {
            Card(accent: .purple) {
                SectionLabel(text: "Your cycle and energy use", accent: .purple)
                Text(phase == .luteal
                     ? "Day \(day). Your resting burn can run a little higher in this part of your cycle. Feeling hungrier this week is normal, so listen to it."
                     : "Day \(day). In the week or two before your period, your resting burn can run a little higher, and feeling hungrier then is normal.")
                    .font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var framingCard: some View {
        Card {
            SectionLabel(text: "How to read this")
            Text("This is what your body used, not a goal to hit or beat. Food is fuel for studying, sleep and recovery. On busy or active days, eating more is your body doing its job.")
                .font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
