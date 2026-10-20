import SwiftUI

/// Setting the smart alarm: the latest she wants to be up, and how early it may wake her.
struct WatchAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var alarm = SmartAlarm.shared
    @State private var latest = WatchAlarmView.defaultLatest
    @State private var window = 30
    @State private var repeats = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Up by").scaledFont(13).foregroundStyle(WatchTint.secondary)
                DatePicker("Up by", selection: $latest, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Picker("Can wake me", selection: $window) {
                    ForEach([10, 20, 30], id: \.self) { Text("\($0) min early").tag($0) }
                }
                .pickerStyle(.navigationLink)
                Toggle("Every day", isOn: $repeats).tint(WatchTint.alarm)
                Button {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: latest)
                    alarm.arm(SmartAlarmPlan(latest: parts.hour! * 60 + parts.minute!, window: window, repeats: repeats))
                    dismiss()
                } label: {
                    Text(alarm.isArmed ? "Save" : "Set alarm").scaledFont(16, .bold).frame(maxWidth: .infinity)
                }
                .tint(WatchTint.alarm)
                if alarm.isArmed {
                    Button("Turn off", role: .destructive) {
                        alarm.turnOff()
                        dismiss()
                    }
                }
                Text("Keep your Watch on overnight. It watches your movement in the window and taps you awake when you’re sleeping lightly, so mornings feel less groggy.")
                    .scaledFont(12).foregroundStyle(WatchTint.secondary)
            }
        }
        .navigationTitle("Smart alarm")
        .sensoryFeedback(.success, trigger: alarm.isArmed)
        .watchScreen(tint: WatchTint.alarm)
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
                .symbolEffect(.pulse)
            Text("Good morning").numberFont(22).foregroundStyle(.white)
            if let last = alarm.lastResult {
                Text(last).scaledFont(12).foregroundStyle(WatchTint.secondary).multilineTextAlignment(.center)
            }
            Button { alarm.stop() } label: {
                Text("Stop").scaledFont(18, .bold).frame(maxWidth: .infinity, minHeight: 50)
            }
            .tint(Color(hex: 0xFFC94D))
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RadialGradient(colors: [WatchTint.alarm.opacity(0.5), .black], center: .top, startRadius: 0, endRadius: 220).ignoresSafeArea()
        }
    }
}

extension View {
    /// A pushed screen's backdrop, matching the page it came from.
    func watchScreen(tint: Color) -> some View {
        containerBackground(for: .navigation) {
            ZStack {
                Color.black
                RadialGradient(colors: [tint.opacity(0.45), tint.opacity(0.12), .clear], center: .topTrailing, startRadius: 0, endRadius: 200)
            }
        }
    }
}
