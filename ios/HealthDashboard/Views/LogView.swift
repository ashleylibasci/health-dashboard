import SwiftUI

/// The Log tab: quick buttons that save straight to Apple Health.
struct LogView: View {
    @Environment(AppModel.self) private var model
    @State private var stress: Int?
    @State private var flow: Int?
    @State private var symptoms: Set<Symptom> = []
    @State private var toast: String?
    @State private var showOther = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Log today").serifTitleFont(32).foregroundStyle(Color.ink).padding(.top, 8)

            section("Caffeine") {
                AdaptiveStack(spacing: 10) {
                    Button { log("Latte saved") { await model.logCaffeine(130) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cup.and.saucer.fill").foregroundStyle(Color.butterInk)
                            VStack(alignment: .leading) { Text("+ Latte").scaledFont(16, .bold); Text("130 mg").scaledFont(12) }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.ink).padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 60)
                        .background(Color.butter, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    Button { showOther.toggle() } label: {
                        Text("+ Other").scaledFont(15, .bold).foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, minHeight: 60).background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
                if showOther {
                    CaffeinePicker { d in log("\(d.name) saved") { await model.logCaffeine(d.mg) } }
                }
            }

            section("Drinks & water") {
                AdaptiveGrid(columns: 4, spacing: 8) {
                    if model.profile?.prefs.drinksTracking ?? true {
                        ForEach(Array(zip(["Wine", "Beer", "Cocktail", "Shot"], [Color.lilac, .butter, .peach, .lavender])), id: \.0) { name, fill in
                            quick(name, fill) { log("\(name) saved") { await model.logDrink() } }
                        }
                    }
                }
                AdaptiveStack(spacing: 8) {
                    Text("Water · \(bottleName(model.bottleMl))").scaledFont(13, .semibold).foregroundStyle(Color.mainText)
                        .frame(width: typeSize.isAccessibilitySize ? nil : 92, alignment: .leading)
                    HStack(spacing: 8) {
                        quick("+ ¼", .lavender, ink: .mainText) { log("¼ bottle saved") { await model.logWater(bottles: 0.25) } }
                        quick("+ ½", .lavender, ink: .mainText) { log("½ bottle saved") { await model.logWater(bottles: 0.5) } }
                        quick("+ 1", .lavender, ink: .mainText) { log("Bottle saved") { await model.logWater(bottles: 1) } }
                    }
                }
                Text("\(bottleCount(model.bottlesToday)) of \(bottleCount(goalBottles(model.bottleMl))) bottles today").scaledFont(13).foregroundStyle(Color.muted)
            }

            section("Stress") {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { n in
                        Button { stress = n } label: {
                            Text("\(n)").numberFont(16).foregroundStyle(Color.ink)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(stress == n ? (n >= 4 ? Color.peach : n <= 2 ? Color.mint : Color.lavender) : Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(stress == n ? RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(n >= 4 ? Color.peachInk : Color.mainText, lineWidth: 2) : nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(["Very calm", "Calm", "Okay", "Stressed", "Very stressed"][n - 1])
                        .accessibilityAddTraits(stress == n ? .isSelected : [])
                    }
                }
                Group {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) { Text("1 is very calm"); Text("5 is very stressed") }
                    } else {
                        HStack { Text("Very calm"); Spacer(); Text("Very stressed") }
                    }
                }
                .scaledFont(12).foregroundStyle(Color.muted)
                Note("Saved to Apple Health as State of Mind.")
            }

            if model.profile?.tracksCycle ?? false {
                section("Cycle") {
                    AdaptiveGrid(columns: 4, spacing: 8) {
                        ForEach(Array(zip([0, 2, 3, 4], ["No flow", "Light", "Medium", "Heavy"])), id: \.0) { level, name in
                            Button { flow = level } label: {
                                Text(name).scaledFont(14, flow == level ? .bold : .semibold).foregroundStyle(Color.ink)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(flow == level ? Color.lavender : Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(flow == level ? RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.mainText, lineWidth: 2) : nil)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(flow == level ? .isSelected : [])
                        }
                    }
                    FlowLayout {
                        ForEach(Symptom.cycle + (model.profile?.conditions.contains(.pcos) == true ? [.acne] : [])) { s in
                            Chip(text: s.rawValue, selected: symptoms.contains(s)) {
                                if symptoms.contains(s) { symptoms.remove(s) } else { symptoms.insert(s) }
                            }
                        }
                    }
                }
            }

            PrimaryButton(title: "Save") { saveSelections() }
                .disabled(stress == nil && flow == nil && symptoms.isEmpty)
                .opacity(stress == nil && flow == nil && symptoms.isEmpty ? 0.4 : 1)
            if let warn = caffeineLimitNote(model.caffeineToday.reduce(0) { $0 + $1.value }) {
                Label(warn, systemImage: "exclamationmark.triangle.fill").scaledFont(14, .semibold).foregroundStyle(Color.peachInk)
                    .padding(12).background(Color.peach, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let toast { Label(toast, systemImage: "checkmark.circle.fill").scaledFont(15, .bold).foregroundStyle(Color.mintInk) }
            if let err = model.lastLogError { Note("Couldn’t save to Apple Health: \(err)") }
        }
        .page()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(title, color: .muted)
            content()
        }
    }

    private func quick(_ name: String, _ fill: Color, ink: Color = .ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name).scaledFont(14, .bold).foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 48).background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func log(_ message: String, _ work: @escaping () async -> Void) {
        Task {
            await work()
            toast = model.lastLogError == nil ? message : nil
        }
    }

    private func saveSelections() {
        let s = stress, f = flow, sym = symptoms
        log("Saved to Apple Health") {
            if let s { await model.logStress(s) }
            if let f {
                let yesterday = Day.shift(model.today, -1)
                await model.logFlow(f, startsPeriod: (model.health.flow[yesterday] ?? 0) == 0)
            }
            for x in sym { await model.logSymptom(x) }
        }
        stress = nil; flow = nil; symptoms = []
    }
}
