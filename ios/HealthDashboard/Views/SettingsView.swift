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
                Section {
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
                    if model.calendarURL != nil {
                        Button("Remove calendar link", role: .destructive) {
                            link = ""
                            Task { await model.setCalendarURL(nil) }
                        }
                    }
                } header: {
                    Text("Google Calendar")
                } footer: {
                    Text("On a computer, open calendar.google.com → the gear → Settings. Click the calendar your exams are in, scroll to “Secret address in iCal format,” and copy it. Send it to your phone (AirDrop or Notes) and paste it here. Treat it like a password: anyone with it can read that calendar. It’s kept in your phone’s Keychain.")
                }

                Section {
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
        }
    }
}
