import SwiftUI

/// The smart alarm on the Sleep tab: what it's set to, whether the Watch has it, and a way to change it.
struct SmartAlarmCard: View {
    @Environment(AppModel.self) private var model
    @State private var link = AlarmLink.shared
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Smart alarm", systemImage: "alarm.fill").scaledFont(15, .bold).foregroundStyle(Color.butterInk)
                Spacer()
                if link.plan != nil { statusBadge }
            }
            if let plan = link.plan {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up by \(plan.latestText)").numberFont(28).foregroundStyle(Color.ink).contentTransition(.numericText())
                    Text("Wakes you in light sleep from \(SmartAlarmPlan(latest: plan.latest - plan.window).latestText)\(plan.repeats ? ", every day" : "")")
                        .scaledFont(14).foregroundStyle(Color.muted2)
                }
                if let note = statusNote { Note(note) }
                if plan.phoneBackup, let at = PhoneBackupAlarm.scheduledFor {
                    Label("Backup on iPhone at \(at.formatted(date: .omitted, time: .shortened))", systemImage: "iphone")
                        .scaledFont(13, .semibold).foregroundStyle(Color.muted2)
                }
                if let mornings = link.watchStatus?.mornings, !mornings.isEmpty { MorningLog(mornings: mornings) }
                HStack(spacing: 10) {
                    Button("Change") { editing = true }.buttonStyle(.bordered)
                    Button("Turn off", role: .destructive) { withAnimation(.snappy) { link.set(nil) } }.buttonStyle(.bordered)
                }
                .scaledFont(15, .semibold)
            } else {
                Text("Your Watch wakes you in light sleep, up to 30 minutes before you need to be up, so mornings feel less groggy.")
                    .scaledFont(15).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Set smart alarm") { editing = true }
            }
            if !WatchSync.shared.watchReady {
                Note("Needs Health Dashboard on your Apple Watch.")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.butter, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.snappy, value: link.plan)
        .animation(.snappy, value: link.watchStatus)
        .sheet(isPresented: $editing) {
            SmartAlarmSheet(plan: link.plan ?? SmartAlarmPlan(latest: suggestedWake)) { link.set($0) }
                .presentationDetents([.medium, .large])
        }
        .onAppear { link.refresh() }
    }

    /// Eight hours after the suggested bedtime, as minutes after midnight.
    private var suggestedWake: Int { (model.bedtimeTarget + 8 * 60 + 18 * 60) % (24 * 60) }

    @ViewBuilder private var statusBadge: some View {
        let (text, icon, ink): (String, String, Color) = switch link.watchStatus?.state {
        case .armed: ("On your Watch", "checkmark.circle.fill", .mintInk)
        case .failed: ("Not set", "exclamationmark.triangle.fill", .peachInk)
        case .waiting: ("Open on Watch", "applewatch", .butterInk)
        default: ("Sending…", "arrow.up.circle", .muted)
        }
        Label(text, systemImage: icon).scaledFont(12, .bold).foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.surface.opacity(0.7), in: Capsule())
    }

    private var statusNote: String? {
        switch link.watchStatus?.state {
        case .waiting: "Open Health Dashboard on your Watch once to finish. watchOS only lets the Watch set alarms while its app is open."
        case .failed: link.watchStatus?.message
        case nil: WatchSync.shared.watchReady ? "Sending to your Watch. It finishes setting when the Watch app is open." : nil
        default: nil
        }
    }
}

/// Picking the time, how early it may wake her, and whether it repeats.
struct SmartAlarmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var plan: SmartAlarmPlan
    var save: (SmartAlarmPlan) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Up by", selection: time, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("The latest you want to be up. It never wakes you later than this.")
                }
                Section {
                    Picker("Can wake me", selection: $plan.window) {
                        ForEach([10, 20, 30], id: \.self) { Text("\($0) min early").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How early")
                } footer: {
                    Text("Within this window, your Watch taps you awake at the first sign of light sleep.")
                }
                Section {
                    Picker("Wakes on", selection: $plan.sensitivity) {
                        ForEach(SmartAlarmPlan.Sensitivity.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Sensitivity")
                } footer: {
                    Text("Gentle waits for more stirring, so it tends to wake you later. Sensitive goes off at smaller movements. If it wakes you too early or never early, change this.")
                }
                Section {
                    Toggle("Every day", isOn: $plan.repeats)
                    if PhoneBackupAlarm.isAvailable {
                        Toggle("Backup alarm on iPhone", isOn: $plan.phoneBackup)
                    }
                } footer: {
                    if PhoneBackupAlarm.isAvailable {
                        Text("Rings on your iPhone at the latest time if your Watch hasn’t woken you, like when it’s not on or the alarm didn’t get set.")
                    }
                }
            }
            .navigationTitle("Smart alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(plan)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    /// The plan's minutes after midnight as a time today, for the picker.
    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: plan.latest / 60, minute: plan.latest % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            plan.latest = (c.hour ?? 8) * 60 + (c.minute ?? 0)
        }
    }
}

/// The last few mornings: how early the Watch woke her, as small bars, plus a line of what it means.
struct MorningLog: View {
    var mornings: [AlarmMorning]

    var body: some View {
        let recent = Array(mornings.suffix(7))
        let early = recent.filter { $0.minutesEarly > 0 }
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST \(recent.count) MORNINGS").labelFont().foregroundStyle(Color.butterInk)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(recent) { m in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(m.minutesEarly > 0 ? Color(hex: 0xE0A800) : Color(hex: 0xE0A800).opacity(0.3))
                            .frame(height: max(6, CGFloat(m.minutesEarly) * 1.6))
                        Text(m.date.formatted(.dateTime.weekday(.narrow))).scaledFont(11, .semibold).foregroundStyle(Color.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 64, alignment: .bottom)
            .accessibilityElement()
            .accessibilityLabel(recent.map { "\($0.date.formatted(.dateTime.weekday(.wide))): \($0.minutesEarly == 0 ? "at the latest time" : "\($0.minutesEarly) minutes early")" }.joined(separator: ", "))
            Text(early.isEmpty ? "It hasn’t found light sleep in the window yet. Try Sensitive."
                 : early.count == recent.count && (early.map(\.minutesEarly).max() ?? 0) >= 25 ? "Usually wakes you near the start of the window. If that’s too early, try Gentle."
                 : "Woke you early on \(early.count) of \(recent.count) mornings.")
                .scaledFont(13).foregroundStyle(Color.muted2)
        }
        .padding(12)
        .background(Color.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
