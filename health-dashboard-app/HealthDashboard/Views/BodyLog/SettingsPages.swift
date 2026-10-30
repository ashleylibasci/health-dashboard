import SwiftUI
import UIKit
import HealthCore

// The pages behind the Settings hub, one per row, each about a screenful.
// The alert toggles live only here (Notifications), not on the screens
// they're about.

// MARK: - Profile

/// Name, age, health conditions and redoing setup.
struct ProfileSettingsView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmRedo = false

    private var nameBinding: Binding<String> {
        Binding(get: { store.data.name ?? "" },
                set: { store.data.name = $0.isEmpty ? nil : $0 })
    }

    private var ageBinding: Binding<Int> {
        Binding(get: { store.data.ageYears ?? 0 },
                set: { store.data.ageYears = $0 > 0 ? $0 : nil })
    }

    var body: some View {
        Screen(title: "Profile", accent: .indigo) {
            Card {
                AdaptiveStack(spacing: 4) {
                    Text("Name").font(.scaled(size: 15, weight: .bold))
                    TextField("Your first name", text: nameBinding)
                        .font(.scaled(size: 15))
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Your name")
                }
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                LabeledControlRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Age").font(.scaled(size: 15, weight: .bold))
                        Text("Optional. Compares your fitness with your own age group.").font(.scaled(size: 13)).secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } control: {
                    Picker("Age", selection: ageBinding) {
                        Text("Not set").tag(0)
                        ForEach(13...90, id: \.self) { age in Text("\(age)").tag(age) }
                    }
                    .pickerStyle(.menu)
                    .tint(Accent.indigo.ink(scheme))
                    .fixedSize()
                }
                .frame(minHeight: 44)
            }
            RowCard {
                MetricRow(title: "Health conditions",
                          note: store.data.conditions.isEmpty ? "None added. Optional, private, stays on your phone" : store.data.conditions.joined(separator: ", "),
                          systemImage: "heart.text.square.fill", accent: .purple) { ConditionsView() }
            }
            Card(density: .compact) {
                SettingsActionRow(title: "Redo setup", systemImage: "arrow.counterclockwise", accent: .indigo) {
                    confirmRedo = true
                }
            }
        }
        .confirmationDialog("Redo setup?", isPresented: $confirmRedo, titleVisibility: .visible) {
            Button("Redo setup") { store.data.onboarded = false }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You\u{2019}ll go through the setup questions again, starting from your current answers, so you only change what you want. Your logs, sleep history and Apple Health data stay.")
        }
    }
}

// MARK: - Calendars

/// Apple or Google Calendar (or a calendar link) for exams, with the way to
/// sign in to Google again, and her exam list.
struct CalendarSettingsView: View {
    var body: some View {
        Screen(title: "Calendars", accent: .yellow) {
            CalendarImportCard()
            RowCard { ExamsLinkRow() }
        }
    }
}

// MARK: - Cycle & birth control

/// Cycle setup, birth-control method and where she is in her pack.
struct CycleSettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var birthControlBinding: Binding<String> {
        Binding(get: { store.data.birthControl ?? "" },
                set: { store.data.birthControl = $0.isEmpty ? nil : $0 })
    }

    private var method: BirthControl? { store.data.birthControl.flatMap(BirthControl.init(rawValue:)) }

    var body: some View {
        let p = Palette(scheme: scheme)
        Screen(title: "Cycle & birth control", accent: .pink) {
            Card(density: .compact) {
                // Stacked at large text sizes: beside the label, the menu's
                // value was squeezed to one letter per line (round 3, A2).
                LabeledControlRow {
                    HStack(spacing: 12) {
                        SettingsIcon(systemImage: "drop.fill", accent: .pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cycle").font(.scaled(size: 15, weight: .bold))
                            Text("What the cycle screens show").font(.scaled(size: 13)).secondaryText()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } control: {
                    Picker("Cycle", selection: $store.data.cycleSetup) {
                        ForEach(AppData.CycleSetup.allCases, id: \.self) { setup in
                            Text(SettingsView.setupName(setup)).tag(setup)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Accent.pink.ink(scheme))
                    .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                    .accessibilityLabel("Cycle setup")
                }
                .frame(minHeight: 44)
                if let reason = model.irregularReasonText {
                    Label(reason, systemImage: "info.circle")
                        .font(.scaled(size: 13, weight: .semibold))
                        .secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                if store.data.cycleSetup == .hormonal {
                    Divider().overlay(p.cardBorder)
                    LabeledControlRow {
                        HStack(spacing: 12) {
                            SettingsIcon(systemImage: "pills.fill", accent: .purple)
                            Text("Method").font(.scaled(size: 15, weight: .bold))
                        }
                    } control: {
                        Picker("Birth control", selection: birthControlBinding) {
                            Text("Choose\u{2026}").tag("")
                            ForEach(BirthControl.allCases, id: \.self) { bc in
                                Text(bc.rawValue).tag(bc.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Accent.purple.ink(scheme))
                        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                        .accessibilityLabel("Birth control method")
                    }
                    .frame(minHeight: 44)
                    if let method {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(method.note).font(.scaled(size: 13)).secondaryText()
                                .fixedSize(horizontal: false, vertical: true)
                            // Shared with Accuracy tips, so the two screens always agree.
                            Text(method.ovulationLine).font(.scaled(size: 13, weight: .semibold))
                                .foregroundStyle(Accent.purple.ink(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Accent.purple.tint(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        LinkRow(title: "Learn about your method", subtitle: "What it does to your cycle, sleep and heart rate",
                                systemImage: "book.fill", accent: .purple) {
                            BirthControlLearnView()
                        }
                    } else {
                        Text("Pick your method so the app knows whether you ovulate and whether you have a pack.")
                            .font(.scaled(size: 13)).secondaryText()
                    }
                }
            }
            // Your pack sits with the method it belongs to.
            if model.packMethod != nil {
                Card {
                    PackSetupControl()
                }
            }
            if store.birthControl == .combinedPill { PillSettingsCard() }
        }
    }
}

// MARK: - Sleep & alarm

/// Bedtime and latest wake-up, the smart alarm's state, and the iPhone
/// backup alarm (always shown, so it's never a hidden setting).
struct SleepSettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @ObservedObject private var backupAlarm = PhoneBackupAlarm.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        Screen(title: "Sleep & alarm", accent: .purple) {
            Card {
                SleepScheduleControl()
            }
            Card(density: .compact) {
                SettingToggleRow(title: "Bedtime nudge", detail: bedtimeNudgeDetail,
                                 systemImage: "moon.haze.fill", accent: .purple, isOn: bedtimeNudgeBinding)
            }
            Card(density: .compact) {
                // The switch itself is on the Sleep tab, next to the alarm it
                // controls (Whitfield F2).
                TabLinkRow(title: "Smart alarm", subtitle: smartAlarmSubtitle,
                           systemImage: "alarm.fill", accent: .orange, tab: .sleep)
                    .accessibilityHint("Opens the Sleep tab")
                Divider().overlay(p.cardBorder)
                SettingToggleRow(title: "iPhone backup alarm", detail: backupAlarmDetail,
                                 systemImage: "iphone.radiowaves.left.and.right", accent: .orange,
                                 isOn: backupAlarmBinding)
                    .disabled(!PhoneBackupAlarm.isAvailable || !store.data.smartAlarmEnabled)
                Divider().overlay(p.cardBorder)
                LinkRow(title: "Wake plan", subtitle: "Why tonight's alarm is set when it is",
                        systemImage: "sunrise.fill", accent: .orange) {
                    WakePlanView()
                }
            }
        }
    }

    /// "Lights low, screens down" 45 minutes before tonight's bedtime
    /// (H-C4). Turning it on asks for notification permission.
    private var bedtimeNudgeBinding: Binding<Bool> {
        Binding(get: { store.data.sleepExtras.bedtimeNudge },
                set: { on in
                    store.data.sleepExtras.bedtimeNudge = on
                    Task {
                        if on { await Nudges.requestPermission() }
                        await model.updateBedtimeNudge()
                    }
                })
    }

    private var bedtimeNudgeDetail: String {
        let at = Clock.format(model.tonightBedtime - BedtimeNudge.lead)
        return store.data.sleepExtras.bedtimeNudge
            ? "Tonight at \(at): \u{201C}Lights low, screens down\u{201D}, \(BedtimeNudge.lead) minutes before bed"
            : "A gentle buzz \(BedtimeNudge.lead) minutes before bed (\(at) tonight): \u{201C}Lights low, screens down\u{201D}"
    }

    /// "On · 8:00–8:25am · never after 8:30am".
    private var smartAlarmSubtitle: String {
        guard store.data.smartAlarmEnabled else {
            return "Off. Turn it on from the Sleep tab or the Tonight card on Today."
        }
        if let window = model.wakePlan()?.alarmWindow {
            return "On \u{00B7} \(window.label) \u{00B7} never after \(Clock.format(store.data.upBy)), your latest wake-up"
        }
        return "On \u{00B7} never after \(Clock.format(store.data.upBy)), your latest wake-up"
    }

    /// Turning it on asks iOS for alarm permission while she's looking.
    private var backupAlarmBinding: Binding<Bool> {
        Binding(get: { store.data.phoneBackupAlarm && PhoneBackupAlarm.isAvailable && store.data.smartAlarmEnabled },
                set: { on in
                    store.data.phoneBackupAlarm = on
                    if on { Task { await PhoneBackupAlarm.shared.requestPermission() } }
                })
    }

    private var backupAlarmDetail: String {
        guard PhoneBackupAlarm.isAvailable else { return "Needs iOS 26.1 or later." }
        guard store.data.smartAlarmEnabled else {
            return "Turn the smart alarm on first. Then a regular iPhone alarm rings at its latest time, in case your Watch can't wake you."
        }
        if backupAlarm.denied {
            return "Alarms are off for Health Dashboard in iOS Settings, so the backup can't ring. Turn them on in Settings \u{2192} Health Dashboard."
        }
        if store.data.phoneBackupAlarm, let at = backupAlarm.scheduledFor {
            return "Rings at \(Clock.format(Clock.minutesOfDay(at))) if your Watch hasn't woken you. Stopping the Watch alarm cancels it."
        }
        return "A regular iPhone alarm at your smart alarm's latest time, in case your Watch can't wake you. Stopping the Watch alarm cancels it."
    }
}

// MARK: - Tracking

/// What the app tracks: water bottle and goal, calories, alcohol, and the
/// drinks on the quick-log list.
struct TrackingSettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    private var caloriesBinding: Binding<Bool> {
        Binding(get: { store.data.showCalories && !model.caloriesHiddenByCondition },
                set: { store.data.showCalories = $0 })
    }

    private var caloriesDetail: String {
        model.caloriesHiddenByCondition
            ? "Off because you added an eating-disorder history. Remove it in Health conditions to turn this on."
            : "Off by default. No targets or food diary."
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        Screen(title: "Tracking", accent: .blue) {
            Card(density: .compact) {
                LinkRow(title: model.hidesEffortTargets ? "Water bottle size" : "Water bottle and daily goal",
                        subtitle: "Bottle \(LogFormat.oz(store.data.bottleSizeML))" + (model.hidesEffortTargets ? "" : " \u{00B7} goal \(LogFormat.oz(store.data.waterGoalML))"),
                        systemImage: "drop.fill", accent: .blue) {
                    WaterView()
                }
                Divider().overlay(p.cardBorder)
                SettingToggleRow(title: "Calories", detail: caloriesDetail,
                                 systemImage: "flame.fill", accent: .orange, isOn: caloriesBinding)
                    .disabled(model.caloriesHiddenByCondition)
                Divider().overlay(p.cardBorder)
                SettingToggleRow(title: "Alcohol tracking", detail: "How alcohol affects sleep and recovery. Off hides alcohol on the Log tab.",
                                 systemImage: "wineglass.fill", accent: .berry, isOn: $store.data.drinksTracking)
                Divider().overlay(p.cardBorder)
                LinkRow(title: "Quick-log drinks",
                        subtitle: store.data.savedDrinks.isEmpty ? "None saved yet" : store.data.savedDrinks.map(\.name).joined(separator: ", "),
                        systemImage: "cup.and.saucer.fill", accent: .yellow) {
                    CaffeineView()
                }
            }
        }
    }
}

// MARK: - Notifications

/// Notifications by moment, not by feature (D-N4): Morning, Daytime and
/// Bedtime, one switch each, saying what that moment sends. The pill
/// reminder keeps its own switch with the pack (one row here points to
/// it), so no moment switch can silence it.
struct NotificationSettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    /// Notifications are switched off for the app in iOS Settings while a
    /// moment is on.
    @State private var notificationsBlocked = false

    var body: some View {
        Screen(title: "Notifications", accent: .coral) {
            Card(density: .compact) {
                SettingToggleRow(title: "Morning",
                                 detail: "One note about 45 minutes after you wake: your recovery, pill day and tonight's bedtime, with Log latte and +1 bottle.",
                                 systemImage: "sun.max.fill", accent: .orange, isOn: morning)
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                SettingToggleRow(title: "Daytime",
                                 detail: "15 minutes before your focus peak and afternoon dip, and a sick alert (at most once a day) when several overnight signals are off.",
                                 systemImage: "bolt.fill", accent: .mint, isOn: daytime)
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                SettingToggleRow(title: "Bedtime",
                                 detail: "\u{201C}Lights low, screens down\u{201D} \(BedtimeNudge.lead) minutes before bed, with Turn on Watch alarm when it's off.",
                                 systemImage: "moon.haze.fill", accent: .purple, isOn: bedtime)
                if notificationsBlocked {
                    blockedNote
                }
            }
            if store.birthControl == .combinedPill {
                RowCard {
                    MetricRow(title: "Pill reminder", note: pillNote, systemImage: "pills.fill", accent: .pink) {
                        CycleSettingsView()
                    }
                }
            }
        }
        .task { await checkNotifications() }
    }

    // MARK: Switches

    private var morning: Binding<Bool> {
        Binding(get: { store.data.insights.morningNote }, set: { on in
            store.data.insights.morningNote = on
            changed(on) { await model.updateMorningNote() }
        })
    }

    /// Peak and dip alerts and the sick alert together. Either on counts as on.
    private var daytime: Binding<Bool> {
        Binding(get: { store.data.peakDipNudges || store.data.sickAlerts }, set: { on in
            store.data.peakDipNudges = on
            store.data.sickAlerts = on
            changed(on) {}
        })
    }

    /// The bedtime nudge (H-C4), also in Sleep & alarm.
    private var bedtime: Binding<Bool> {
        Binding(get: { store.data.sleepExtras.bedtimeNudge }, set: { on in
            store.data.sleepExtras.bedtimeNudge = on
            changed(on) { await model.updateBedtimeNudge() }
        })
    }

    /// "On · 9pm, set with your pack"
    private var pillNote: String {
        store.data.pillReminder ? "On \u{00B7} \(Clock.format(store.data.pillTime)), set with your pack" : "Off \u{00B7} set with your pack"
    }

    private var blockedNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Notifications are off for this app", systemImage: "bell.slash.fill")
                .font(.scaled(size: 14, weight: .bold))
                .foregroundStyle(Accent.coral.ink(scheme))
            Text("Turn them on in the iPhone Settings app, under Notifications, so these can reach you.")
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open iPhone Settings", destination: url)
                    .font(.scaled(size: 14, weight: .semibold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 4)
    }

    /// Turning a moment on asks for notification permission (the system
    /// prompt only shows the first time), then reschedules.
    private func changed(_ on: Bool, reschedule: @escaping () async -> Void) {
        Task {
            if on { await Nudges.requestPermission() }
            await reschedule()
            await checkNotifications()
        }
    }

    private func checkNotifications() async {
        let wanted = store.data.insights.morningNote || store.data.peakDipNudges || store.data.sickAlerts
            || store.data.sleepExtras.bedtimeNudge
        notificationsBlocked = wanted ? !(await Nudges.isAllowed()) : false
    }
}

// MARK: - Widgets & Watch

/// Where to find each place the app shows up outside itself (Whitfield F10),
/// one row each, opened in place.
struct WidgetsWatchSettingsView: View {
    struct HowTo: Identifiable {
        var id: String { title }
        let title: String
        let systemImage: String
        let steps: String
    }

    static let howTos: [HowTo] = [
        HowTo(title: "Home Screen widget", systemImage: "apps.iphone",
              steps: "Touch and hold an empty spot on your Home Screen, tap Edit, then Add Widget, and search for Health Dashboard. Pick Recovery, Cycle, Caffeine & water, or Bedtime streak."),
        HowTo(title: "Lock Screen widget", systemImage: "lock.iphone",
              steps: "Touch and hold your Lock Screen, tap Customize, then Lock Screen, and tap the space under the time to add one."),
        HowTo(title: "Watch app", systemImage: "applewatch",
              steps: "It installs with this app. Press the Digital Crown and open Health Dashboard: recovery, energy, tonight and quick logging."),
        HowTo(title: "Watch face", systemImage: "applewatch.watchface",
              steps: "Touch and hold your watch face, tap Edit, swipe to Complications, tap a spot and choose Health Dashboard."),
    ]

    var body: some View {
        Screen(title: "Widgets & Watch", accent: .indigo) {
            RowCard {
                ForEach(Array(Self.howTos.enumerated()), id: \.element.id) { i, howTo in
                    if i > 0 { RowDivider() }
                    ExpandRow(title: howTo.title, summary: "How to add it", systemImage: howTo.systemImage, accent: .indigo) {
                        Text(howTo.steps).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Apple Health & data

/// Where the numbers come from (Apple Health or example data), getting
/// accurate numbers, privacy, export and deleting everything.
struct DataSettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var confirmDelete = false
    @State private var confirmSample = false
    /// The logs as CSV, written when the page opens (G4).
    @State private var csvFile: URL?

    var body: some View {
        let p = Palette(scheme: scheme)
        Screen(title: "Apple Health & data", accent: .pink) {
            Card {
                HStack(spacing: 10) {
                    if model.loading {
                        ProgressView()
                    } else {
                        Image(systemName: model.usingSampleData ? "doc.text.magnifyingglass" : "checkmark.circle.fill")
                            .foregroundStyle((model.usingSampleData ? Accent.yellow : Accent.mint).ink(scheme))
                            .accessibilityHidden(true)
                    }
                    Text(dataStatus).font(.scaled(size: 14)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                Divider().overlay(p.cardBorder)
                SettingsActionRow(title: "Connect Apple Health", systemImage: "heart.fill", accent: .pink) {
                    Task { await model.connectHealth() }
                }
                .disabled(model.loading)
                Divider().overlay(p.cardBorder)
                SettingsActionRow(title: "Use example data instead", systemImage: "wand.and.stars", accent: .indigo) {
                    confirmSample = true
                }
                .disabled(model.loading || model.prefersSampleData)
            }
            RowCard {
                MetricRow(title: "Getting accurate numbers", note: "Watch fit, settings and small habits",
                          systemImage: "checklist", accent: .mint) { AccuracyTipsView() }
            }
            if store.data.cycleSetup != .notTracking {
                Card {
                    // G3: her history survives a reinstall.
                    SettingToggleRow(title: "Save bleeding and symptoms to Apple Health",
                                     detail: "Flow, spotting, symptoms and your birth-control method, so they\u{2019}re kept if you reinstall and Apple\u{2019}s Cycle Tracking sees them too. Turning it off leaves what\u{2019}s saved in Health.",
                                     systemImage: "heart.text.square.fill", accent: .pink,
                                     isOn: Binding(get: { store.data.savesCycleToHealth },
                                                   set: { on in Task { await model.setSavesCycleToHealth(on) } }))
                }
            }
            Card {
                HStack(alignment: .top, spacing: 12) {
                    SettingsIcon(systemImage: "lock.fill", accent: .mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Everything stays on your phone").font(.scaled(size: 15, weight: .bold))
                        Text("Your check-ins, drinks and cycle setup are saved only on this iPhone. Health data stays in Apple Health. Nothing is uploaded.")
                            .font(.scaled(size: 13))
                            .secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                Divider().overlay(p.cardBorder)
                ShareLink(item: exportText) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.scaled(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Accent.indigo.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityHidden(true)
                        Text("Export data").font(.scaled(size: 15, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let csvFile {
                    // G4: the logs as one spreadsheet.
                    Divider().overlay(p.cardBorder)
                    ShareLink(item: csvFile) {
                        HStack(spacing: 12) {
                            Image(systemName: "tablecells")
                                .font(.scaled(size: 15, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .background(Accent.indigo.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export logs as a spreadsheet").font(.scaled(size: 15, weight: .semibold))
                                Text("Sleep, caffeine, water, alcohol, check-ins and mood, as CSV")
                                    .font(.scaled(size: 13)).secondaryText()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .foregroundStyle(Accent.indigo.ink(scheme))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider().overlay(p.cardBorder)
                SettingsActionRow(title: "Delete all data", systemImage: "trash", accent: .pink, role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .task { csvFile = model.writeLogsCSV() }
        .confirmationDialog("Show example data?", isPresented: $confirmSample, titleVisibility: .visible) {
            Button("Show example data") { model.loadSample() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app shows example nights, heart readings and energy instead of yours, and keeps them until you tap Connect Apple Health. What you log stays saved. Nothing in Apple Health changes.")
        }
        .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all data and restart setup", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes everything this app saved on your phone: check-ins, drinks, water, cycle logs, exams and settings. It cancels the app\u{2019}s reminders and turns off the smart alarm, then starts setup again. Your Apple Health data isn\u{2019}t touched.")
        }
    }

    private var dataStatus: String {
        if model.loading { return "Loading from Apple Health\u{2026}" }
        if model.prefersSampleData { return "Example data (you chose this). Tap Connect Apple Health to use your own." }
        switch model.healthConnection {
        case .unavailable: return "Apple Health isn\u{2019}t available on this device, so the app shows example data."
        case .notAsked: return "Showing example data. Connect Apple Health to use your own."
        case .noSleepYet: return "No sleep from Apple Health yet, so the app shows example data. If you turned off access, open the Settings app, then Health, then Data Access."
        default: break
        }
        return model.usingSampleData
            ? "Using your Apple Health data. The rest is example data until you have \(AppModel.nightsNeeded) nights (\(min(model.realNightCount, AppModel.nightsNeeded)) so far)."
            : "Using your Apple Health data."
    }

    private var exportText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(store.data), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// Starting over goes back to setup, which connects Apple Health again
    /// (not example data).
    private func deleteAll() {
        store.data = AppData()
        Task {
            await Nudges.cancelPeakDip()
            await BedtimeReminders.cancelAll()
        }
    }
}

// MARK: - Appearance

/// Dark (the default), Light, or Match iPhone, as three small previews.
struct AppearanceSettingsView: View {
    /// "dark" (default), "light" or "system". Read by the app root.
    @AppStorage("appearance") private var appearance = "dark"
    /// After her wind-down the backgrounds turn warmer and darker (D-M6).
    @AppStorage("eveningDim") private var eveningDim = true
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    private struct Mode: Identifiable {
        let id: String
        let name: String
        let note: String
    }

    private static let modes: [Mode] = [
        Mode(id: "dark", name: "Dark", note: "Dark is the default. It matches your Watch and is easier on your eyes at night."),
        Mode(id: "light", name: "Light", note: "Every screen keeps the same layout and colors for each metric, on a light background."),
        Mode(id: "system", name: "Match iPhone", note: "Follows your iPhone\u{2019}s Light or Dark setting, and switches with it if you set it to Automatic."),
    ]

    /// "Dark", "Light" or "Match iPhone", for the Settings row.
    static func name(_ id: String) -> String {
        (modes.first { $0.id == id } ?? modes[0]).name
    }

    var body: some View {
        Screen(title: "Appearance", accent: .purple) {
            HStack(spacing: 10) {
                ForEach(Self.modes) { mode in
                    card(mode)
                }
            }
            Text((Self.modes.first { $0.id == appearance } ?? Self.modes[0]).note)
                .font(.scaled(size: 13))
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Card(density: .compact) {
                SettingToggleRow(title: "Evening dim", detail: eveningDimNote, systemImage: "moon.haze.fill",
                                 accent: .purple, isOn: $eveningDim)
            }
            .padding(.top, Space.s)
        }
    }

    /// "From your wind-down at 9:45pm, …"
    private var eveningDimNote: String {
        let start = AmbientLook.windDownStart(model).map { " at \(Clock.format($0))" } ?? ""
        return "From your wind-down\(start), the background turns a little warmer and darker. It follows the clock, not your numbers."
    }

    private func card(_ mode: Mode) -> some View {
        let p = Palette(scheme: scheme)
        let on = appearance == mode.id
        let accent = Accent.indigo.ink(scheme)
        return Button { appearance = mode.id } label: {
            VStack(spacing: 8) {
                AppearanceThumb(mode: mode.id)
                Text(mode.name)
                    .font(.scaled(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ZStack {
                    Circle().strokeBorder(on ? accent : p.tertiary, lineWidth: 2)
                    Circle().fill(on ? accent : Color.clear).frame(width: 10, height: 10)
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(on ? Accent.indigo.fill(scheme).opacity(scheme == .dark ? 0.2 : 0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(on ? accent : p.cardBorder, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.name) appearance")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A tiny phone screen showing what each appearance looks like.
private struct AppearanceThumb: View {
    let mode: String

    private var dark: Color { .black }
    private var light: Color { Color(hex: 0xF6F6FA) }

    private var background: LinearGradient {
        switch mode {
        case "light":
            return LinearGradient(colors: [light, light], startPoint: .leading, endPoint: .trailing)
        case "system":
            return LinearGradient(stops: [.init(color: dark, location: 0.5), .init(color: light, location: 0.5)],
                                  startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [dark, dark], startPoint: .leading, endPoint: .trailing)
        }
    }

    private var tile: Color {
        switch mode {
        case "light": return .white
        case "system": return Color(hex: 0xA0A0B4, alpha: 0.45)
        default: return Color.white.opacity(0.18)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 6) {
            Circle()
                .strokeBorder(Color(hex: 0x5B6BE8), lineWidth: 4)
                .frame(width: 22, height: 22)
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tile)
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tile)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .frame(width: 64, height: 92)
        .background(background, in: shape)
        .overlay(shape.strokeBorder(Color(hex: 0x9A9DB5, alpha: 0.4)))
        .accessibilityHidden(true)
    }
}

// MARK: - Shared pieces

/// A rounded-square icon for a settings row.
private struct SettingsIcon: View {
    var systemImage: String
    var accent: Accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.scaled(size: 16, weight: .semibold))
            .foregroundStyle(accent.ink(scheme))
            .frame(width: 36, height: 36)
            .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A full-width button row in a settings card: icon and title in the accent.
private struct SettingsActionRow: View {
    var title: String
    var systemImage: String
    var accent: Accent
    var role: ButtonRole? = nil
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.scaled(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                Text(title).font(.scaled(size: 15, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(accent.ink(scheme))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
