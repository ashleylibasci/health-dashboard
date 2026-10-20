import SwiftUI

/// Setting the smart alarm: the latest she wants to be up, and how early it may wake her.
struct WatchAlarmView: View {
    @State private var alarm = SmartAlarm.shared
    @State private var latest = WatchAlarmView.defaultLatest
    @State private var window = 30
    @State private var repeats = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Smart alarm").scaledFont(15, .bold).foregroundStyle(Color.mainText)
                if alarm.isArmed, let plan = alarm.plan {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Up by").scaledFont(13).foregroundStyle(Color(hex: 0x4A4F6E))
                        Text(plan.latestText).numberFont(36).foregroundStyle(Color.ink)
                        Text("Wakes you in light sleep from \(SmartAlarmPlan(latest: plan.latest - plan.window).latestText)\(plan.repeats ? ", every day" : "")")
                            .scaledFont(12).foregroundStyle(Color(hex: 0x4A4F6E))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.lavender, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Button("Turn off", role: .destructive) { alarm.turnOff() }
                } else {
                    Text("Up by").scaledFont(13).foregroundStyle(Color(hex: 0x4A4F6E))
                    DatePicker("Up by", selection: $latest, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Picker("Can wake me", selection: $window) {
                        ForEach([10, 20, 30], id: \.self) { Text("\($0) min early").tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                    Toggle("Every day", isOn: $repeats)
                    Button {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: latest)
                        alarm.arm(SmartAlarmPlan(latest: parts.hour! * 60 + parts.minute!, window: window, repeats: repeats))
                    } label: {
                        Text("Set alarm").scaledFont(15, .bold).frame(maxWidth: .infinity)
                    }
                    .tint(.main)
                }
                if let error = alarm.error { Text(error).scaledFont(12, .bold).foregroundStyle(Color.peachInk) }
                if let last = alarm.lastResult { Text(last).scaledFont(12).foregroundStyle(Color(hex: 0x4A4F6E)) }
                Text("Keep your Watch on overnight. It watches your movement in the window and taps you awake when you’re sleeping lightly, so mornings feel less groggy.")
                    .scaledFont(12).foregroundStyle(Color(hex: 0x4A4F6E))
            }
        }
        .foregroundStyle(Color.ink)
        .watchPage(.ground)
        .onAppear {
            guard let p = alarm.plan else { return }
            latest = Calendar.current.date(bySettingHour: p.latest / 60, minute: p.latest % 60, second: 0, of: .now) ?? latest
            window = p.window
            repeats = p.repeats
        }
    }

    private static var defaultLatest: Date { Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now)! }
}

/// Full screen while the alarm is buzzing.
struct WatchRingingView: View {
    @State private var alarm = SmartAlarm.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.horizon.fill").font(.system(size: 40)).foregroundStyle(Color(hex: 0xFFC94D))
            Text("Good morning").numberFont(22).foregroundStyle(.white)
            if let last = alarm.lastResult {
                Text(last).scaledFont(12).foregroundStyle(Color.white.opacity(0.75)).multilineTextAlignment(.center)
            }
            Button { alarm.stop() } label: {
                Text("Stop").scaledFont(18, .bold).frame(maxWidth: .infinity, minHeight: 50)
            }
            .tint(Color(hex: 0xFFC94D))
        }
        .padding(.horizontal, 6)
        .watchPage(.black)
    }
}
