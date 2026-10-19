import SwiftUI

/// The Log tab: quick buttons that save straight to Apple Health, plus period and symptom logging
/// for any day through the day sheet.
struct LogView: View {
    @Environment(AppModel.self) private var model
    @State private var stress: Int?
    @State private var toast: Toast?
    @State private var showOther = false
    @State private var when = Date.now
    @State private var customTime = false
    @State private var busy = false
    @State private var editingDay: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Log").font(.serifTitle(32)).foregroundStyle(Color.ink).padding(.top, 8)

            if model.profile?.tracksCycle ?? false { cycleSection }

            section("Caffeine") {
                WhenPicker(date: $when, custom: $customTime)
                HStack(spacing: 10) {
                    Button { log("Latte saved") { await model.logCaffeine(130, name: "Latte", at: time) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cup.and.saucer.fill").foregroundStyle(Color.butterInk)
                            VStack(alignment: .leading) { Text("+ Latte").font(.headline); Text("130 mg").font(.caption) }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.ink).padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 60)
                        .background(Color.butter, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    Button { showOther.toggle() } label: {
                        Text(showOther ? "Hide drinks" : "+ Other").font(.headline).foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, minHeight: 60).background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
                .disabled(busy)
                if showOther {
                    CaffeinePicker { d in log("\(d.name) saved") { await model.logCaffeine(d.mg, name: d.name, at: time) } }
                        .disabled(busy)
                }
                if let warn = caffeineLimitNote(model.caffeineToday.reduce(0) { $0 + $1.value }) {
                    Label(warn, systemImage: "exclamationmark.triangle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.peachInk)
                        .padding(12).background(Color.peach, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                NavigationLink { CaffeineView() } label: {
                    Text("Today: \(Int(model.caffeineToday.reduce(0) { $0 + $1.value })) mg · see or change times ›")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.mainText)
                }
            }

            section("Drinks & water") {
                if model.profile?.prefs.drinksTracking ?? true {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                        ForEach(Array(zip(["Wine", "Beer", "Cocktail", "Shot"], [Color.lilac, .butter, .peach, .lavender])), id: \.0) { name, fill in
                            quick(name, fill) { log("\(name) saved · \(model.drinksTonight + 1) tonight") { await model.logDrink(name, at: time) } }
                        }
                    }
                    Text("Uses the time above too.").font(.caption).foregroundStyle(Color.muted)
                }
                HStack(spacing: 8) {
                    Text("Water · \(bottleName(model.bottleMl))").font(.subheadline.weight(.semibold)).foregroundStyle(Color.mainText)
                    quick("+ ¼", .lavender, ink: .mainText) { log("¼ bottle saved") { await model.logWater(bottles: 0.25) } }
                    quick("+ ½", .lavender, ink: .mainText) { log("½ bottle saved") { await model.logWater(bottles: 0.5) } }
                    quick("+ 1", .lavender, ink: .mainText) { log("Bottle saved") { await model.logWater(bottles: 1) } }
                }
                Text("\(bottleCount(model.bottlesToday)) of \(bottleCount(goalBottles(model.bottleMl))) bottles today").font(.caption).foregroundStyle(Color.muted)
            }

            section("Stress right now") {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { n in
                        Button {
                            stress = n
                            log("Saved to Apple Health as State of Mind") { await model.logStress(n) }
                        } label: {
                            Text("\(n)").font(.number(16)).foregroundStyle(Color.ink)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(stress == n ? (n >= 4 ? Color.peach : n <= 2 ? Color.mint : Color.lavender) : Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .accessibilityLabel(["Very calm", "Calm", "Okay", "Stressed", "Very stressed"][n - 1])
                        .accessibilityAddTraits(stress == n ? .isSelected : [])
                    }
                }
                HStack { Text("Very calm"); Spacer(); Text("Very stressed") }.font(.caption).foregroundStyle(Color.muted)
            }
        }
        .page()
        .toolbar(.hidden, for: .navigationBar)
        .toast($toast)
        .sheet(item: Binding(get: { editingDay.map { IdentifiedDay(day: $0) } }, set: { editingDay = $0?.day })) { d in
            DayLogSheet(day: d.day)
        }
    }

    private var time: Date { customTime ? when : .now }

    /// Period and symptoms: shows what's already logged today, and opens the day sheet for today or any recent day.
    private var cycleSection: some View {
        section("Period & symptoms") {
            let todayLog = model.dayLog(model.today)
            Button { editingDay = model.today } label: {
                HStack(spacing: 12) {
                    FlowDrops(level: todayLog.flow ?? 0).frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today").font(.headline).foregroundStyle(Color.ink)
                        Text(summary(todayLog)).font(.subheadline).foregroundStyle(Color.muted).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Text(todayLog.flow == nil && todayLog.symptoms.isEmpty ? "Log" : "Edit").font(.subheadline.weight(.bold)).foregroundStyle(Color.mainText)
                }
                .padding(14)
                .background(Color.rose, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("Forgot a day?").font(.subheadline.weight(.bold)).foregroundStyle(Color.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { back in
                        let day = Day.shift(model.today, -back)
                        let saved = model.dayLog(day)
                        Button { editingDay = day } label: {
                            VStack(spacing: 4) {
                                Text(back == 1 ? "Yest." : Day.weekdayName(day)).font(.caption.weight(.semibold))
                                Text("\(Int(day.suffix(2))!)").font(.headline)
                                FlowDrops(level: saved.flow ?? -1)
                            }
                            .foregroundStyle(Color.ink)
                            .frame(width: 54, height: 78)
                            .background(saved.flow.map { $0 >= 1 ? Color.rose : Color.surface } ?? Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(Day.short(day)): \(summary(saved)). Tap to log or edit.")
                    }
                }
            }
        }
    }

    private func summary(_ log: (flow: Int?, symptoms: Set<Symptom>)) -> String {
        let flow = log.flow.map { ["No bleeding", "Spotting", "Light", "Medium", "Heavy"][$0] }
        let parts = [flow] + log.symptoms.map(\.rawValue).sorted().map { Optional($0) }
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? "Nothing logged yet" : text
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(title, color: .muted)
            content()
        }
    }

    private func quick(_ name: String, _ fill: Color, ink: Color = .ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name).font(.subheadline.weight(.bold)).foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 48).background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    /// One save at a time (so a double tap can't log twice), then a toast that clears itself.
    private func log(_ message: String, _ work: @escaping () async -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            await work()
            busy = false
            toast = model.lastLogError.map { Toast(text: "Couldn’t save: \($0)", isError: true) } ?? Toast(text: message)
            if customTime { customTime = false; when = .now }
        }
    }
}

struct IdentifiedDay: Identifiable {
    var day: String
    var id: String { day }
}
