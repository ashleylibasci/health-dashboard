import SwiftUI
import HealthCore

/// Settings → Cycle & birth control, combined pill: the pill reminder and
/// its time, and reading doses from Apple Health (H-A1).
struct PillSettingsCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let p = Palette(scheme: scheme)
        Card(density: .compact) {
            SettingToggleRow(title: "Pill reminder", detail: reminderDetail,
                             systemImage: "bell.fill", accent: .pink, isOn: reminderBinding)
            if store.data.pillReminder {
                LabeledControlRow {
                    Text("Pill time").font(.scaled(size: 15, weight: .bold))
                } control: {
                    DatePicker("Pill time", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(Accent.pink.ink(scheme))
                }
                .frame(minHeight: 44)
            }
            Divider().overlay(p.cardBorder)
            SettingToggleRow(title: "Also read pill doses from Apple Health", detail: healthDetail,
                             systemImage: "heart.text.square.fill", accent: .pink, isOn: healthBinding)
                .disabled(!PillHealth.isSupported)
        }
    }

    private var time: String { Clock.format(store.data.pillTime) }

    private var reminderDetail: String {
        if model.appleRemindsPill {
            return "Apple\u{2019}s Medications already reminds you, so this app only checks back an hour after \(time) if no dose is logged. New-pack day also gets a heads-up the evening before."
        }
        return "At \(time) on pill days, and once more an hour later if you haven\u{2019}t tapped Taken. New-pack day gets the most: a heads-up the evening before and two repeats."
    }

    private var healthDetail: String {
        guard PillHealth.isSupported else { return "Needs iOS 26 or later." }
        return "MyPill doesn\u{2019}t share with Apple Health, so the app can\u{2019}t see doses you log there. This reads doses from Apple\u{2019}s Medications in the Health app, or any app that saves doses to Health. A dose logged there counts as Taken here, so you never get two reminders. When Health asks, share just your pill."
    }

    /// Turning it on asks for notification permission while she's looking.
    private var reminderBinding: Binding<Bool> {
        Binding(get: { store.data.pillReminder },
                set: { on in
                    if on { Task { await Nudges.requestPermission(); await model.updatePillReminders() } }
                    store.data.pillReminder = on
                })
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { Clock.date(store.data.pillTime, relativeTo: Calendar.current.startOfDay(for: .now)) },
                set: { store.data.pillTime = Clock.minutesOfDay($0) })
    }

    /// Turning it on shows Health's list of her medications to share.
    private var healthBinding: Binding<Bool> {
        Binding(get: { store.data.pillReadsHealth && PillHealth.isSupported },
                set: { on in
                    store.data.pillReadsHealth = on
                    guard on, !DemoMode.isOn else { return }
                    Task {
                        _ = await PillHealth.requestAccess(model.health.store)
                        PillHealth.startWatching(model)
                        await model.updatePill()
                    }
                })
    }
}
