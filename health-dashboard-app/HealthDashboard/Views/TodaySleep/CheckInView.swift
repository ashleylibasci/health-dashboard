import SwiftUI
import Charts
import HealthCore

/// The 10-second morning check-in: how awake, plus anything unusual.
struct CheckInView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var level = 0
    @State private var tags: Set<String> = []
    @State private var loaded = false
    @State private var selectedDay: Date? = nil
    @State private var selectCount = 0
    @State private var savedCount = 0

    /// The question, in the past tense after noon (Dubois 24).
    static var prompt: String {
        Calendar.current.component(.hour, from: .now) >= 12 ? "How awake were you this morning?" : "How awake do you feel?"
    }

    private let names = ["Like a zombie", "Groggy", "Okay", "Good", "Wide awake"]
    private let tagOptions = ["Woke up in the night", "Vivid dreams", "Too warm", "Late screen time", "Alcohol", "Cramps"]

    var body: some View {
        let p = Palette(scheme: scheme)
        Screen(title: "Check-in", accent: .orange) {
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(p.secondary)
                .padding(.top, 4)
            if model.canCheckInNow {
                checkInBody
            } else {
                // Between midnight and the app's day change, a check-in would
                // land on the evening before, so it waits until morning.
                Card(accent: .orange) {
                    SectionLabel(text: "Morning check-in", accent: .orange)
                    Text("Check in after you wake up")
                        .font(.scaled(size: 20, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("It's still last night for the app until \(Clock.format(AppDay.rolloverMinutes)). Come back in the morning and tell it how awake you feel.")
                        .font(.scaled(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if history.count >= 2 {
                    historyCard
                }
            }
        }
        .onAppear(perform: loadExisting)
        .sensoryFeedback(.selection, trigger: selectCount)
        .sensoryFeedback(.success, trigger: savedCount)
    }

    @ViewBuilder
    private var checkInBody: some View {
        let p = Palette(scheme: scheme)
        Card(accent: .orange) {
            SectionLabel(text: "Morning check-in \u{00B7} 10 seconds", accent: .orange)
            Text(alarmLine)
                .font(.scaled(size: 15))
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 0) {
            Text(Self.prompt)
                .font(.heading)
                .accessibilityAddTraits(.isHeader)
            InfoButton(title: "Morning check-in",
                       meaning: "A quick rating of how awake you feel, from 1 (like a zombie) to 5 (wide awake), plus anything unusual about last night.",
                       forYou: "Do it every morning. Over a couple of weeks it teaches the app your real sleep need and which wake times work best for you.")
                .padding(.vertical, -12)
        }
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { n in
                levelButton(n)
            }
        }
        HStack {
            Text(names[0])
            Spacer()
            Text(names[4])
        }
        .font(.scaled(size: 12, weight: .semibold))
        .foregroundStyle(p.secondary)
        .accessibilityHidden(true)
        if level > 0 {
            Label("Saved for today. Tap another number to change it.", systemImage: "checkmark.circle.fill")
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(Accent.mint.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .motionTransition(.reveal, edge: .top)
        }
        Text("Anything last night?")
            .font(.scaled(size: 17, weight: .bold))
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
        // Wider cells at larger text sizes (one column at the largest), so tags wrap instead of clipping.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: min(Font.scaledSize(140), 280)), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(tagOptions, id: \.self) { tag in
                tagButton(tag)
            }
        }
        // D-P3: optional context for Patterns.
        HStack(spacing: 0) {
            Text("Anything going on?")
                .font(.scaled(size: 17, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            InfoButton(title: "Anything going on?",
                       meaning: "Optional tags for the things your Watch can't see: an exam today, studying late, a workout yesterday, a party last night or feeling sick.",
                       forYou: "Tag the mornings they apply to. Once you have enough, Patterns compares those nights with your others and shows any clear difference in your sleep, HRV or resting heart rate.")
                .padding(.vertical, -12)
        }
        .padding(.top, 4)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: min(Font.scaledSize(140), 280)), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(DayTag.allCases) { tag in
                tagButton(tag.rawValue, label: tag.label)
            }
        }
        if level > 0 {
            Card(accent: .orange) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Accent.mint.ink(scheme))
                        .accessibilityHidden(true)
                    Text(reply)
                        .font(.scaled(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            NavigationLink {
                EnergyView()
            } label: {
                Text("See today's energy")
                    .font(.scaled(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(scheme == .dark ? Color(hex: 0x1A0E00) : .white)
                    .background(Accent.orange.ink(scheme), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        if history.count >= 2 {
            historyCard
        }
        Button {
            dismiss()
        } label: {
            Text(level > 0 ? "Done" : "Skip today")
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(p.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: History

    private var history: [AppData.CheckIn] { model.checkIns(lastDays: 14) }

    private var selectedCheckIn: AppData.CheckIn? {
        guard let selectedDay else { return nil }
        return history.min { abs($0.date.timeIntervalSince(selectedDay)) < abs($1.date.timeIntervalSince(selectedDay)) }
    }

    @ViewBuilder
    private var historyReadout: some View {
        if let c = selectedCheckIn {
            let level = min(max(c.awake, 1), 5)
            ChartReadout(title: c.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                         value: "\(level) \u{00B7} \(names[level - 1])",
                         detail: c.tags.isEmpty ? "Nothing unusual noted." : c.tags.joined(separator: ", "),
                         accent: level >= 4 ? .mint : level == 3 ? .orange : .coral)
        } else {
            let avg = history.map { Double($0.awake) }.mean ?? 0
            ChartReadout(title: "Last 2 weeks \u{00B7} \(history.count) check-ins",
                         value: "Average " + String(format: "%.1f", avg) + " of 5",
                         detail: "Touch a bar to see that morning.", accent: .orange)
        }
    }

    private var historyCard: some View {
        Card {
            Text("Your recent mornings").font(.scaled(size: 17, weight: .bold))
            historyReadout
            CheckInHistoryChart(history: history, selected: selectedCheckIn?.date, selection: $selectedDay)
                .frame(height: 140)
            ScrubHint()
        }
    }

    // MARK: Copy

    private var alarmLine: String {
        guard model.lastNightIsFresh else { return "No sleep was recorded last night, so this check-in is saved on its own." }
        let night = model.lastNight
        let stage = night.wokeFromLight ? "in light sleep" : "from deep or REM sleep"
        return "You woke at \(Clock.format(night.wake)), \(stage)."
    }

    private var reply: String {
        if level >= 4 {
            // Only the smart alarm wakes her at the end of a cycle; without it, don't claim it.
            guard store.data.smartAlarmEnabled else {
                return "Nice. Good mornings help the app learn which wake times work best for you."
            }
            let counts = model.lightSleepWakeCount(lastNights: 15)
            if counts.total > 0 {
                return "Nice. Waking at the end of a cycle is working for you. That makes \(counts.light) light-sleep mornings out of \(counts.total)."
            }
            return "Nice. Waking at the end of a cycle is working for you."
        }
        if level == 3 {
            let energy = model.energyToday
            let peak = energy.zone(.morningPeak).map { ($0.range.start + $0.range.end) / 2 } ?? energy.highest.time
            return "Thanks. Your peak today should still land around \(Clock.format(peak))."
        }
        return "Thanks. Rough mornings teach the app most: they help it find the wake times that work best for you."
    }

    // MARK: Actions

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        if let existing = store.checkIn(on: .now) {
            level = existing.awake
            // "Drinks" was the alcohol tag's old name.
            tags = Set(existing.tags.map { $0 == "Drinks" ? "Alcohol" : $0 })
        }
    }

    private func save() {
        guard level > 0 else { return }
        if store.checkIn(on: .now) == nil { savedCount += 1 } else { selectCount += 1 }
        model.saveCheckIn(awake: level, tags: (tagOptions + DayTag.allCases.map(\.rawValue)).filter { tags.contains($0) })
    }

    // MARK: Controls

    private func levelButton(_ n: Int) -> some View {
        let p = Palette(scheme: scheme)
        let on = n == level
        return Button {
            withMotion(.select) { level = n }
            save()
        } label: {
            Text("\(n)")
                .font(.scaledNumber(22))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(on ? Color(hex: 0x1A0E00) : p.primary)
                .background(on ? Accent.orange.fill(scheme) : p.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(on ? Accent.orange.fill(scheme) : p.cardBorder))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(n), \(names[n - 1])")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func tagButton(_ tag: String, label: String? = nil) -> some View {
        let p = Palette(scheme: scheme)
        let on = tags.contains(tag)
        return Button {
            if on { tags.remove(tag) } else { tags.insert(tag) }
            if level > 0 { save() } else { selectCount += 1 }
        } label: {
            Text(label ?? tag)
                .font(.scaled(size: 14, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(on ? Color(hex: 0x1A0E00) : p.primary)
                .background(on ? Accent.orange.fill(scheme) : p.chip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(on ? Accent.orange.fill(scheme) : p.cardBorder))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Recent check-ins as bars, 1 to 5.
private struct CheckInHistoryChart: View {
    let history: [AppData.CheckIn]
    let selected: Date?
    @Binding var selection: Date?
    @Environment(\.colorScheme) private var scheme

    private func color(_ c: AppData.CheckIn) -> Color {
        let base = c.awake >= 4 ? Accent.mint.fill(scheme) : c.awake == 3 ? Accent.orange.fill(scheme) : Accent.coral.fill(scheme)
        guard let selected else { return base }
        return Calendar.current.isDate(c.date, inSameDayAs: selected) ? base : base.opacity(0.35)
    }

    private var summary: String {
        "Morning check-ins, oldest first: " + history.map { "\($0.awake)" }.joined(separator: ", ") + " out of 5."
    }

    var body: some View {
        Chart {
            ForEach(history, id: \.date) { c in
                BarMark(x: .value("Day", c.date, unit: .day), y: .value("Awake", c.awake))
                    .foregroundStyle(color(c))
                    .cornerRadius(4)
            }
        }
        .chartScrub($selection, snapped: selected, steps: history.map(\.date).sorted())
        .chartYScale(domain: 0...5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 3, 5])
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .accessibilityLabel(summary)
    }
}
