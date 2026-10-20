import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var addingSamples = false
    @State private var sampleMessage: String?
    @State private var confirmRerun = false
    @State private var showLink = false
    @State private var linkError: String?

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
                            if let start = profile.packStart {
                                DatePicker("Current pack started", selection: Binding(get: { start }, set: { model.profile?.packStart = $0 }), in: ...Date.now, displayedComponents: .date)
                            } else {
                                Button("Current pack started: not set. Set it") { model.profile?.packStart = Calendar.current.startOfDay(for: .now) }
                            }
                        }
                        NavigationLink("Health conditions\(profile.conditions.isEmpty ? "" : " (\(profile.conditions.count))")") { ConditionsView() }
                        Toggle("Birthday (for fitness age)", isOn: Binding(
                            get: { profile.birthday != nil },
                            set: { model.profile?.birthday = $0 ? Calendar.current.date(byAdding: .year, value: -20, to: .now) : nil }))
                        if let birthday = profile.birthday {
                            DatePicker("Birthday", selection: Binding(get: { birthday }, set: { model.profile?.birthday = $0 }), in: ...Date.now, displayedComponents: .date)
                        }
                        Picker("Water bottle", selection: Binding(get: { profile.bottleMl }, set: { model.profile?.bottleMl = $0 })) {
                            ForEach(bottleSizes, id: \.ml) { Text($0.name).tag($0.ml) }
                        }
                        Toggle("Show calories", isOn: Binding(get: { profile.prefs.showCalories }, set: { model.profile?.prefs.showCalories = $0 }))
                        Toggle("Body-working-harder alerts", isOn: Binding(get: { profile.prefs.sickAlerts }, set: { model.profile?.prefs.sickAlerts = $0 }))
                        Toggle("Drinks tracking", isOn: Binding(get: { profile.prefs.drinksTracking }, set: { model.profile?.prefs.drinksTracking = $0 }))
                        Toggle("Streaks", isOn: Binding(get: { profile.prefs.streaks }, set: { model.profile?.prefs.streaks = $0 }))
                        Toggle("Night version after 8pm", isOn: Binding(get: { profile.prefs.nightMode }, set: { model.profile?.prefs.nightMode = $0 }))
                        Toggle("Dark Watch screens at night", isOn: Binding(get: { profile.prefs.darkWatchAtNight }, set: { model.profile?.prefs.darkWatchAtNight = $0 }))
                        Button("Run the welcome setup again") { confirmRerun = true }
                            .confirmationDialog("Go through the welcome screens again?", isPresented: $confirmRerun, titleVisibility: .visible) {
                                Button("Start welcome setup") {
                                    model.rerunWelcome()
                                    dismiss()
                                }
                            } message: {
                                Text("Your answers start filled in, your pill pack and logs are kept, and nothing in Apple Health changes.")
                            }
                    } header: {
                        Text("Your profile")
                    } footer: {
                        Text("Kept on your phone only.")
                    }
                }

                Section {
                    switch model.calendarSource {
                    case .google? where model.googleNeedsSignIn: Label("Google signed you out", systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.peachInk)
                    case .google?: Label("Google Calendar (signed in)", systemImage: "checkmark.circle.fill").foregroundStyle(Color.mintInk)
                    case .apple?: Label("Apple Calendar", systemImage: "checkmark.circle.fill").foregroundStyle(Color.mintInk)
                    case .link?: Label("Google secret link", systemImage: "checkmark.circle.fill").foregroundStyle(Color.mintInk)
                    case nil: EmptyView()
                    }
                    if model.calendarSource != .google || model.googleNeedsSignIn {
                        Button(model.googleNeedsSignIn ? "Sign in with Google again" : model.googleConfigured ? "Sign in with Google" : "Sign in with Google (needs setup)") { Task { await model.connectGoogle() } }
                            .disabled(!model.googleConfigured)
                    }
                    if model.calendarSource != .apple {
                        Button("Use Apple Calendar") { Task { await model.connectDeviceCalendar() } }
                    }
                    if case .failed(let message) = model.calendarState { Text(message).font(.footnote).foregroundStyle(Color.peachInk) }
                    DisclosureGroup("Or use a secret link") {
                        HStack {
                            if showLink {
                                TextField("Paste the secret address", text: $link)
                            } else {
                                SecureField("Paste the secret address", text: $link)
                            }
                            Button(showLink ? "Hide" : "Show") { showLink.toggle() }.font(.footnote)
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button("Save calendar link") {
                            linkError = nil
                            Task {
                                await model.setCalendarURL(link)
                                // Only close once it actually works; otherwise say why right here.
                                if case .failed(let message) = model.calendarState { linkError = message } else { dismiss() }
                            }
                        }
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let linkError { Text(linkError).font(.footnote).foregroundStyle(Color.peachInk) }
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
                } footer: {
                    // Which build is installed, so she can tell an update landed.
                    Text("Health Dashboard \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .padding(.top, 8)
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
