import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var addingSamples = false
    @State private var sampleMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let profile = model.profile {
                    Section {
                        TextField("Name", text: Binding(get: { profile.name }, set: { model.profile?.name = $0 }))
                        Picker("Cycle", selection: Binding(get: { profile.cycle }, set: { model.profile?.cycle = $0 })) {
                            ForEach(CycleMode.allCases) { Text($0.title).tag($0) }
                        }
                        if profile.cycle == .hormonal {
                            Picker("Birth control", selection: Binding(get: { profile.birthControl }, set: { model.profile?.birthControl = $0 })) {
                                Text("Not set").tag(BirthControl?.none)
                                ForEach(BirthControl.allCases) { Text($0.name).tag(Optional($0)) }
                            }
                        }
                        if profile.cycle == .hormonal, profile.birthControl?.hasPlaceboWeek == true {
                            DatePicker("Current pack started", selection: Binding(get: { profile.packStart ?? .now }, set: { model.profile?.packStart = $0 }), in: ...Date.now, displayedComponents: .date)
                        }
                        NavigationLink("Health conditions\(profile.conditions.isEmpty ? "" : " (\(profile.conditions.count))")") { ConditionsView() }
                        DatePicker("Birthday", selection: Binding(get: { profile.birthday ?? Calendar.current.date(byAdding: .year, value: -20, to: .now)! }, set: { model.profile?.birthday = $0 }), in: ...Date.now, displayedComponents: .date)
                        Picker("Water bottle", selection: Binding(get: { profile.bottleMl }, set: { model.profile?.bottleMl = $0 })) {
                            ForEach(bottleSizes, id: \.ml) { Text($0.name).tag($0.ml) }
                        }
                        Toggle("Show calories", isOn: Binding(get: { profile.prefs.showCalories }, set: { model.profile?.prefs.showCalories = $0 }))
                        Toggle("Body-working-harder alerts", isOn: Binding(get: { profile.prefs.sickAlerts }, set: { model.profile?.prefs.sickAlerts = $0 }))
                        Toggle("Drinks tracking", isOn: Binding(get: { profile.prefs.drinksTracking }, set: { model.profile?.prefs.drinksTracking = $0 }))
                        Toggle("Streaks", isOn: Binding(get: { profile.prefs.streaks }, set: { model.profile?.prefs.streaks = $0 }))
                        Toggle("Night version after 8pm", isOn: Binding(get: { profile.prefs.nightMode }, set: { model.profile?.prefs.nightMode = $0 }))
                        Toggle("Dark Watch screens at night", isOn: Binding(get: { profile.prefs.darkWatchAtNight }, set: { model.profile?.prefs.darkWatchAtNight = $0 }))
                        Button("Run the welcome setup again") {
                            model.profile = nil
                            dismiss()
                        }
                    } header: {
                        Text("Your profile")
                    } footer: {
                        Text("Kept on your phone only.")
                    }
                }

                Section {
                    switch model.calendarSource {
                    case .google?: Label("Google Calendar (signed in)", systemImage: "checkmark.circle.fill").foregroundStyle(Color.mintInk)
                    case .apple?: Label("Apple Calendar", systemImage: "checkmark.circle.fill").foregroundStyle(Color.mintInk)
                    case .link?: Label("Google secret link", systemImage: "checkmark.circle.fill").foregroundStyle(Color.mintInk)
                    case nil: EmptyView()
                    }
                    if model.calendarSource != .google {
                        Button(model.googleConfigured ? "Sign in with Google" : "Sign in with Google (needs setup)") { Task { await model.connectGoogle() } }
                            .disabled(!model.googleConfigured)
                    }
                    if model.calendarSource != .apple {
                        Button("Use Apple Calendar") { Task { await model.connectDeviceCalendar() } }
                    }
                    if case .failed(let message) = model.calendarState { Text(message).font(.footnote).foregroundStyle(Color.peachInk) }
                    DisclosureGroup("Or use a secret link") {
                        SecureField("Paste the secret address", text: $link)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save calendar link") {
                            Task {
                                await model.setCalendarURL(link)
                                dismiss()
                            }
                        }
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                        Text("On a computer: calendar.google.com → the gear → Settings → your calendar → “Secret address in iCal format.” Treat it like a password; it’s kept in your phone’s Keychain.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.isCalendarConnected {
                        Button("Disconnect calendar", role: .destructive) {
                            link = ""
                            Task { await model.disconnectCalendar() }
                        }
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Google reads your calendar straight from Google. Apple Calendar reads the calendars on this iPhone. Both are read-only, and events never leave your phone.")
                }

                Section {
                    switch model.notificationsAllowed {
                    case true?: Label("Reminders are on", systemImage: "checkmark.circle.fill").foregroundStyle(Color.mintInk)
                    case false?:
                        Button("Reminders are off: open Settings to turn them on") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    case nil: Button("Turn on reminders") { Task { await model.requestNotifications() } }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Only two kinds: the night before an exam, and when your body’s working harder than usual.")
                }

                Section {
                    if model.historyLooksShort { ShortHistoryNote() }
                    Text("The app reads sleep, resting heart rate, HRV and caffeine from Apple Health each time you open it. To change what it can read: Settings app → Health → Data Access & Devices → Health Dashboard.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Apple Health")
                }

                #if targetEnvironment(simulator)
                Section {
                    Button(addingSamples ? "Adding…" : "Add 11 weeks of sample data") {
                        addingSamples = true
                        Task {
                            do {
                                try await SampleData.add()
                                sampleMessage = "Added. Pull down on Today to refresh."
                                await model.refreshHealth()
                            } catch {
                                sampleMessage = error.localizedDescription
                            }
                            addingSamples = false
                        }
                    }
                    .disabled(addingSamples)
                    if let sampleMessage { Text(sampleMessage).font(.footnote) }
                } header: {
                    Text("Simulator only")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { link = model.calendarURL ?? "" }
            .task { await model.checkNotifications() }
        }
    }
}
