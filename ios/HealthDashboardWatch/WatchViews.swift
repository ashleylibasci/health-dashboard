import SwiftUI
import WatchKit

/// The Watch app: one full-screen page per feature. Swipe left and right between them; the Digital
/// Crown scrolls within a page. Each page glows in its own color. The smart alarm sits right after
/// Tonight, and the getting-sick heads-up comes first when it's on.
struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @State private var page = WatchRootView.startPage
    @State private var alarm = SmartAlarm.shared

    var body: some View {
        let s = store.snapshot
        NavigationStack {
            TabView(selection: $page) {
                if s.sick { WatchSickView().tag(WatchPage.sick) }
                WatchRecoveryView().tag(WatchPage.recovery)
                WatchTonightView { withAnimation(.snappy) { page = .alarm } }.tag(WatchPage.tonight)
                WatchAlarmPage().tag(WatchPage.alarm)
                WatchLogView().tag(WatchPage.log)
                WatchCycleView().tag(WatchPage.cycle)
            }
            .tabViewStyle(.page)
        }
        .onOpenURL { url in
            guard let p = url.host.flatMap(WatchPage.init(link:)) else { return }
            withAnimation(.snappy) { page = p }
        }
        // Closing the cover any way at all stops the alarm, so it can never keep buzzing out of reach.
        .fullScreenCover(isPresented: Binding(get: { alarm.ringing }, set: { if !$0 { alarm.stop() } })) {
            WatchRingingView().interactiveDismissDisabled()
        }
    }

    /// Test builds can open a page directly with `-page tonight` (etc.).
    private static var startPage: WatchPage {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-page"), i + 1 < args.count, let p = WatchPage(link: args[i + 1]) { return p }
        #endif
        return WatchStore.shared.snapshot.sick ? .sick : .recovery
    }
}

enum WatchPage: Hashable {
    case sick, recovery, tonight, log, alarm, cycle

    /// The page a complication's `healthdashboard://<host>` link opens.
    init?(link: String) {
        switch link {
        case "sick": self = .sick
        case "recovery": self = .recovery
        case "tonight": self = .tonight
        case "log", "water": self = .log
        case "alarm": self = .alarm
        case "cycle": self = .cycle
        default: return nil
        }
    }
}

/// Each page's color: the title, the glow behind the page, and its accents.
enum WatchTint {
    static let recovery = Color(hex: 0x7C8BFF)
    static let tonight = Color(hex: 0x9B86FF)
    static let log = Color(hex: 0xFFD666)
    static let alarm = Color(hex: 0xFFA94D)
    static let cycle = Color(hex: 0xFF8A80)
    static let sick = Color(hex: 0xFF8A65)
    static let water = Color(hex: 0x6FB8FF)
    static let mood = Color(hex: 0x5EE0C1)
    static let drink = Color(hex: 0xD9A6FF)
    /// Secondary text on the dark pages.
    static let secondary = Color.white.opacity(0.72)
}

/// Sizes that follow the screen, so the same page fits a 41mm and a 49mm Watch.
enum WatchSize {
    static let width = WKInterfaceDevice.current().screenBounds.width
    static func scaled(_ points: CGFloat) -> CGFloat { (points * width / 205).rounded() }
}

// MARK: Recovery

struct WatchRecoveryView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let s = store.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WatchHeader(title: "Recovery", tint: WatchTint.recovery)
                HStack(spacing: 10) {
                    WatchRing(value: s.isFromToday ? s.recovery : nil, size: WatchSize.scaled(76), tint: WatchTint.recovery)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.isFromToday ? s.headline : "Not updated yet").scaledFont(17, .bold).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        if let usual = s.usualRecovery { Text("Usual is \(usual)").scaledFont(13).foregroundStyle(WatchTint.secondary) }
                    }
                }
                HStack(spacing: 0) {
                    VsNormalGauge(label: s.hrvChange.map { "HRV \(signedPercent($0))" } ?? "HRV", value: s.hrv,
                                  position: 0.5 + (s.hrvChange ?? 0) * 2.5, tint: Color(hex: 0xFF9A7A))
                    VsNormalGauge(label: s.restingHrChange.map { "RHR \(signedWhole($0))" } ?? "RHR", value: s.restingHr,
                                  position: 0.5 + (s.restingHrChange ?? 0) / 10, tint: Color(hex: 0xFF6B8A))
                    VsNormalGauge(label: "Sleep", text: s.sleepMinutes.map { String(format: "%.1fh", Double($0) / 60) },
                                  position: Double(s.sleepMinutes ?? 0) / 540, tint: WatchTint.mood)
                }
                if s.recoveryWeek.count >= 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LAST \(s.recoveryWeek.count) DAYS").scaledFont(12, .semibold).foregroundStyle(WatchTint.secondary)
                        WeekBars(scores: s.recoveryWeek, late: s.recoveryWeekLate, endsToday: s.isFromToday && s.recovery != nil)
                    }
                    .padding(10)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                if s.updated == .distantPast {
                    Text("Open Health Dashboard on your iPhone to send today’s numbers.").scaledFont(13).foregroundStyle(WatchTint.secondary)
                } else if !s.isFromToday {
                    Text("These are yesterday’s numbers. Open the app on your iPhone to update.").scaledFont(13).foregroundStyle(WatchTint.secondary)
                }
            }
            .animation(.snappy, value: s)
            .watchMargins()
        }
        .watchPage(tint: WatchTint.recovery)
    }

    private func signedPercent(_ x: Double) -> String {
        let n = Int((x * 100).rounded())
        return n == 0 ? "±0%" : "\(n > 0 ? "+" : "−")\(abs(n))%"
    }

    private func signedWhole(_ x: Double) -> String {
        let n = Int(x.rounded())
        return n == 0 ? "±0" : "\(n > 0 ? "+" : "−")\(abs(n))"
    }
}

/// A small dial: the dot sits in the middle on a normal day and swings either way from there.
struct VsNormalGauge: View {
    var label: String
    var value: Int? = nil
    var text: String? = nil
    var position: Double
    var tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Gauge(value: min(1, max(0, position))) {
                EmptyView()
            } currentValueLabel: {
                Text(text ?? value.map(String.init) ?? "–").contentTransition(.numericText())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [tint.opacity(0.55), tint]))
            Text(label).scaledFont(12, .semibold).foregroundStyle(WatchTint.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The week's recovery as bars; nights after a 2am bedtime in peach, today brightest.
struct WeekBars: View {
    var scores: [Int]
    var late: [Bool]
    /// Whether the last bar is today's score (it isn't until today's is in).
    var endsToday = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(scores.indices, id: \.self) { i in
                let isToday = endsToday && i == scores.count - 1
                let isLate = i < late.count && late[i]
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isLate ? Color(hex: 0xFF9A7A) : WatchTint.recovery.opacity(isToday ? 1 : 0.45))
                    .frame(height: max(6, 34 * CGFloat(scores[i]) / 100))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 34, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("Recovery for the last \(scores.count) days: \(scores.map(String.init).joined(separator: ", "))")
    }
}

// MARK: Tonight

struct WatchTonightView: View {
    @Environment(WatchStore.self) private var store
    @State private var alarm = SmartAlarm.shared
    /// Moves to the smart alarm page, right next door.
    var showAlarm: () -> Void

    var body: some View {
        let s = store.snapshot
        let bed = s.bedtimeMinutes ?? 390
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchHeader(title: "Tonight", tint: WatchTint.tonight)
                SleepDial(bedtime: bed, hours: 8)
                    .frame(width: WatchSize.scaled(118), height: WatchSize.scaled(118))
                    .frame(maxWidth: .infinity)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("BED BY").scaledFont(12, .semibold).foregroundStyle(WatchTint.tonight)
                        Text(clock(bed)).numberFont(20).foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("UP AT").scaledFont(12, .semibold).foregroundStyle(WatchTint.alarm)
                        Text(clock(bed + 8 * 60)).numberFont(20).foregroundStyle(.white)
                    }
                }
                Button(action: showAlarm) {
                    HStack(spacing: 8) {
                        Image(systemName: "alarm.fill").foregroundStyle(WatchTint.alarm)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Smart alarm").scaledFont(14, .semibold).foregroundStyle(.white)
                            Text(alarm.isArmed ? alarm.plan.map { "Up by \($0.latestText)" } ?? "On" : alarm.isWaiting ? "Open to finish setting" : "Off · tap to set")
                                .scaledFont(12).foregroundStyle(WatchTint.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").scaledFont(12, .bold).foregroundStyle(WatchTint.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(WatchTint.alarm.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressScale())
                if let note = s.examNote {
                    WatchPill(icon: "calendar", tint: WatchTint.log, text: note)
                }
                if let c = s.caffeineAtBed, c >= 1 {
                    WatchPill(icon: "cup.and.saucer.fill", tint: WatchTint.log, text: "~\(Int(c.rounded())) mg caffeine at bed")
                }
            }
            .watchMargins()
        }
        .watchPage(tint: WatchTint.tonight, at: .top)
    }

    /// Minutes after 6pm as a clock time, like "12:15am".
    private func clock(_ minutesAfter6pm: Int) -> String {
        let t = (minutesAfter6pm + 18 * 60) % (24 * 60)
        let h = t / 60, m = t % 60
        return String(format: "%d:%02d%@", h % 12 == 0 ? 12 : h % 12, m, h < 12 ? "am" : "pm")
    }
}

/// A 12-hour clock with tonight's sleep as an arc: a moon where it starts, a sun where it ends.
struct SleepDial: View {
    /// Bedtime in minutes after 6pm.
    var bedtime: Int
    var hours: Int

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line = size * 0.12
            let start = Double((bedtime + 18 * 60) % 720) / 720
            let length = Double(hours * 60) / 720
            let radius = (size - line) / 2
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: line)
                Circle()
                    .trim(from: 0, to: length)
                    .stroke(AngularGradient(colors: [WatchTint.tonight, WatchTint.alarm], center: .center, startAngle: .zero, endAngle: .degrees(length * 360)),
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(start * 360 - 90))
                ForEach([(0, "12"), (3, "3"), (6, "6"), (9, "9")], id: \.0) { hour, label in
                    let angle = Double(hour) / 12 * 2 * .pi - .pi / 2
                    Text(label).scaledFont(10, .semibold).foregroundStyle(.white.opacity(0.45))
                        .offset(x: cos(angle) * (radius - line * 1.4), y: sin(angle) * (radius - line * 1.4))
                }
                endpoint("moon.fill", WatchTint.tonight, at: start, radius: radius, line: line)
                endpoint("sun.max.fill", WatchTint.alarm, at: start + length, radius: radius, line: line)
                VStack(spacing: 0) {
                    Text("\(hours)h").numberFont(26).foregroundStyle(.white)
                    Text("of sleep").scaledFont(12, .semibold).foregroundStyle(WatchTint.secondary)
                }
            }
            .frame(width: size, height: size)
        }
        .accessibilityElement()
        .accessibilityLabel("\(hours) hours of sleep planned")
    }

    private func endpoint(_ icon: String, _ tint: Color, at fraction: Double, radius: CGFloat, line: CGFloat) -> some View {
        let angle = fraction * 2 * .pi - .pi / 2
        return Image(systemName: icon)
            .font(.system(size: line * 0.7, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: line * 1.4, height: line * 1.4)
            .background(Color(hex: 0x1A1245), in: Circle())
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
    }
}

// MARK: Log

struct WatchLogView: View {
    @Environment(WatchStore.self) private var store
    @State private var askingMood = false

    var body: some View {
        let s = store.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    WatchHeader(title: "Log", tint: WatchTint.log)
                    Spacer()
                    Text("cutoff 2pm").scaledFont(12, .semibold).foregroundStyle(WatchTint.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    LogTile(title: "Latte", detail: "\(Int(s.caffeineToday)) of 400 mg", shortDetail: "\(Int(s.caffeineToday)) mg", icon: "cup.and.saucer.fill",
                            tint: WatchTint.log, progress: s.caffeineToday / 400) { await store.logLatte() }
                    LogTile(title: "Water", detail: "\(bottles(s.waterToday)) of \(bottles(s.waterGoal))", icon: "drop.fill",
                            tint: WatchTint.water, progress: s.waterToday / max(1, s.waterGoal)) { await store.logWater() }
                    LogTile(title: "Drink", detail: "Tap to log", icon: "wineglass.fill", tint: WatchTint.drink) { await store.logDrink() }
                    LogTile(title: "Mood", detail: "How’s today?", icon: "face.smiling", tint: WatchTint.mood) { askingMood = true }
                }
                .disabled(store.saving)
            }
            .animation(.snappy, value: s)
            .watchMargins()
        }
        .overlay(alignment: .bottom) {
            if let msg = store.lastLogged {
                Label(msg, systemImage: msg.hasPrefix("Couldn") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .scaledFont(13, .semibold).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: msg) {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { store.lastLogged = nil }
                    }
            }
        }
        .animation(.snappy, value: store.lastLogged)
        .sensoryFeedback(.success, trigger: store.lastLogged) { _, new in new != nil && !(new?.hasPrefix("Couldn") ?? true) }
        .sheet(isPresented: $askingMood) { MoodPicker { level in
            askingMood = false
            Task { await store.logMood(level) }
        } }
        .watchPage(tint: WatchTint.log)
    }

    private func bottles(_ x: Double) -> String {
        let q = Int((x * 4).rounded())
        let frac = ["", "¼", "½", "¾"][q % 4]
        return q / 4 == 0 && !frac.isEmpty ? frac : "\(q / 4)\(frac)"
    }
}

/// One square logging button: an icon (with a progress ring when there's a daily target), a name and today's amount.
struct LogTile: View {
    var title: String
    var detail: String
    /// Used instead of `detail` where it doesn't fit (a 41mm Watch, large text).
    var shortDetail: String? = nil
    var icon: String
    var tint: Color
    var progress: Double? = nil
    var action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Circle().fill(tint.opacity(progress == nil ? 0.22 : 0))
                    if let progress {
                        Circle().stroke(tint.opacity(0.25), lineWidth: 4)
                        Circle().trim(from: 0, to: min(1, progress))
                            .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                }
                .frame(width: 34, height: 34)
                Spacer(minLength: 0)
                Text(title).scaledFont(16, .bold).foregroundStyle(.white)
                ViewThatFits(in: .horizontal) {
                    Text(detail)
                    Text(shortDetail ?? detail).minimumScaleFactor(0.8)
                }
                .scaledFont(12, .semibold).foregroundStyle(WatchTint.secondary).lineLimit(1)
                .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, minHeight: WatchSize.scaled(84), alignment: .leading)
            .padding(10)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("\(title), \(detail)")
    }
}

/// Five faces from very calm to very stressed.
struct MoodPicker: View {
    var pick: (Int) -> Void
    private let options = [(1, "Very calm", "face.smiling.inverse"), (2, "Calm", "face.smiling"), (3, "Okay", "minus.circle"),
                           (4, "Stressed", "exclamationmark.circle"), (5, "Very stressed", "exclamationmark.triangle")]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("How’s today?").scaledFont(16, .bold).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(options, id: \.0) { level, name, icon in
                    Button { pick(level) } label: {
                        Label(name, systemImage: icon).scaledFont(15, .semibold).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tint(WatchTint.mood)
                }
            }
        }
    }
}

/// Buttons shrink a touch while pressed, so a tap feels like it landed.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: Smart alarm

struct WatchAlarmPage: View {
    @State private var alarm = SmartAlarm.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    WatchHeader(title: "Smart alarm", tint: WatchTint.alarm)
                    Spacer()
                    if alarm.isArmed {
                        Label("On", systemImage: "circle.fill").labelStyle(.titleAndIcon)
                            .scaledFont(12, .bold).foregroundStyle(Color(hex: 0x6EE79A))
                    }
                }
                if alarm.ringing {
                    Button { alarm.stop() } label: {
                        Label("Stop alarm", systemImage: "stop.fill").scaledFont(16, .bold).frame(maxWidth: .infinity)
                    }
                    .tint(Color(hex: 0xFFC94D))
                } else if alarm.isArmed, let plan = alarm.plan {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Up by").scaledFont(13).foregroundStyle(WatchTint.secondary)
                        Text(plan.latestText).numberFont(40).foregroundStyle(.white)
                            .minimumScaleFactor(0.7).lineLimit(1)
                    }
                    WakeWindow(plan: plan, movement: alarm.lastWindow)
                    NavigationLink { WatchAlarmView() } label: {
                        Text("Change").scaledFont(15, .semibold).frame(maxWidth: .infinity)
                    }
                    .tint(WatchTint.alarm)
                } else if let plan = alarm.plan {
                    // Set (maybe from the iPhone) but not scheduled: watchOS only allows that with the app open.
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Up by").scaledFont(13).foregroundStyle(WatchTint.secondary)
                        Text(plan.latestText).numberFont(40).foregroundStyle(.white.opacity(0.6))
                            .minimumScaleFactor(0.7).lineLimit(1)
                    }
                    Button {
                        Task { await alarm.arm(plan) }
                    } label: {
                        HStack(spacing: 6) {
                            if alarm.arming { ProgressView().frame(width: 18, height: 18) }
                            Text(alarm.arming ? "Setting…" : "Finish setting").scaledFont(16, .bold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(WatchTint.alarm)
                    .disabled(alarm.arming)
                    NavigationLink { WatchAlarmView() } label: {
                        Text("Change").scaledFont(15, .semibold).frame(maxWidth: .infinity)
                    }
                    Button("Turn off", role: .destructive) { alarm.turnOff() }
                } else {
                    Text("Wakes you in light sleep, up to 30 minutes before you need to be up.")
                        .scaledFont(15).foregroundStyle(WatchTint.secondary)
                    NavigationLink { WatchAlarmView() } label: {
                        Label("Set alarm", systemImage: "alarm.fill").scaledFont(16, .bold).frame(maxWidth: .infinity)
                    }
                    .tint(WatchTint.alarm)
                }
                if let error = alarm.error { Text(error).scaledFont(12, .bold).foregroundStyle(Color(hex: 0xFF8A80)) }
                if let last = alarm.lastResult { Text(last).scaledFont(12).foregroundStyle(WatchTint.secondary) }
                if alarm.mornings.count >= 2 {
                    let recent = alarm.mornings.suffix(5).map { $0.minutesEarly == 0 ? "on time" : "\($0.minutesEarly)m early" }
                    Text("Recent mornings: " + recent.joined(separator: ", "))
                        .scaledFont(12).foregroundStyle(WatchTint.secondary)
                }
            }
            .animation(.snappy, value: alarm.isArmed)
            .watchMargins()
        }
        .watchPage(tint: WatchTint.alarm, at: .topTrailing)
    }
}

/// The wake window: last night's wrist movement across it when there is some, else just the window.
struct WakeWindow: View {
    var plan: SmartAlarmPlan
    var movement: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(WatchTint.alarm.opacity(0.16))
                if movement.count >= 2 {
                    let top = max(movement.max() ?? 0, 0.02)
                    let slots = max(movement.count, plan.window * 2)
                    GeometryReader { geo in
                        Path { p in
                            for (i, m) in movement.enumerated() {
                                let pt = CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(slots - 1),
                                                 y: geo.size.height * (0.9 - 0.75 * CGFloat(min(1, m / top))))
                                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                            }
                        }
                        .stroke(WatchTint.alarm, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(height: 36)
            HStack {
                Text(SmartAlarmPlan(latest: plan.latest - plan.window).latestText)
                Spacer()
                Text(movement.count >= 2 ? "last night" : "window").foregroundStyle(.white)
                Spacer()
                Text(plan.latestText)
            }
            .scaledFont(11, .semibold).foregroundStyle(WatchTint.secondary)
        }
        .padding(8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Wake window from \(SmartAlarmPlan(latest: plan.latest - plan.window).latestText) to \(plan.latestText)")
    }
}

// MARK: Cycle

struct WatchCycleView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let s = store.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let length = s.typicalLength, let day = s.cycleDay {
                    WatchHeader(title: "Cycle", tint: WatchTint.cycle)
                    PhaseRing(day: day, length: length, periodLength: s.periodLength ?? 5, ovulation: s.ovulationDay ?? length - 14, phase: s.phase)
                        .frame(width: WatchSize.scaled(100), height: WatchSize.scaled(100))
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 6) {
                        if let d = s.daysToPeriod, d >= 0 {
                            WatchStat(label: "Period", value: d == 0 ? "Today" : "~\(d) day\(d == 1 ? "" : "s")", tint: Color(hex: 0xF07A6B))
                        }
                        if let t = s.tempDelta {
                            WatchStat(label: "Wrist temp", value: "\(t >= 0 ? "+" : "−")\(String(format: "%.1f", abs(t)))°", tint: Color(hex: 0xC9CFFF))
                        }
                    }
                    if s.phase == "Luteal" {
                        Text("Lower HRV is expected this week.").scaledFont(13).foregroundStyle(WatchTint.secondary)
                    }
                } else if let day = s.cycleDay {
                    WatchHeader(title: "Pill pack", tint: WatchTint.cycle)
                    Text("Day \(day)").numberFont(40).foregroundStyle(.white)
                    if let p = s.phase { Text(p).scaledFont(15).foregroundStyle(WatchTint.secondary) }
                } else {
                    WatchHeader(title: "Cycle", tint: WatchTint.cycle)
                    Image(systemName: "circle.dashed").font(.system(size: 36, weight: .semibold)).foregroundStyle(WatchTint.cycle)
                    Text("Nothing to show yet").scaledFont(17, .bold).foregroundStyle(.white)
                    Text("Turn on cycle tracking in Settings on your iPhone, or log your period there. Your cycle shows up here after the iPhone app next opens.")
                        .scaledFont(13).foregroundStyle(WatchTint.secondary)
                }
            }
            .watchMargins()
        }
        .watchPage(tint: WatchTint.cycle, at: .top)
    }
}

/// The cycle as a ring of phase colors, with a dot on today.
struct PhaseRing: View {
    var day: Int, length: Int, periodLength: Int, ovulation: Int
    var phase: String? = nil

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line = size * 0.11
            ZStack {
                segment(1, periodLength, Color(hex: 0xF07A6B), line)
                segment(periodLength + 1, ovulation - 2, Color(hex: 0xFFD2BD), line)
                segment(ovulation - 1, ovulation + 1, Color(hex: 0x7C8BFF), line)
                segment(ovulation + 2, length, Color(hex: 0xC9CFFF), line)
                let angle = (Double(min(day, length)) - 0.5) / Double(length) * 2 * .pi - .pi / 2
                Circle().fill(.white).overlay(Circle().stroke(.black, lineWidth: 3))
                    .frame(width: line * 1.5, height: line * 1.5)
                    .offset(x: cos(angle) * (size - line) / 2, y: sin(angle) * (size - line) / 2)
                VStack(spacing: 0) {
                    Text("\(day)").numberFont(size * 0.32).foregroundStyle(.white)
                    if let phase { Text(phase.uppercased()).scaledFont(11, .bold).foregroundStyle(Color(hex: 0xC9CFFF)) }
                }
            }
            .frame(width: size, height: size)
        }
        .accessibilityElement()
        .accessibilityLabel("Cycle day \(day)\(phase.map { ", \($0)" } ?? "")")
    }

    private func segment(_ from: Int, _ to: Int, _ color: Color, _ line: CGFloat) -> some View {
        Circle()
            .trim(from: CGFloat(from - 1) / CGFloat(length) + 0.006, to: CGFloat(max(from, to)) / CGFloat(length) - 0.006)
            .stroke(color, lineWidth: line)
            .rotationEffect(.degrees(-90))
            .padding(line / 2)
    }
}

// MARK: Heads up

struct WatchSickView: View {
    @Environment(WatchStore.self) private var store
    @State private var answered = false

    var body: some View {
        let s = store.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchHeader(title: "Heads up", tint: WatchTint.sick)
                Image(systemName: "thermometer.medium").font(.system(size: 30, weight: .semibold)).foregroundStyle(WatchTint.sick)
                Text("Body working harder").scaledFont(18, .bold).foregroundStyle(.white)
                Text("Bug coming on, or stress? Just a guess.").scaledFont(14).foregroundStyle(WatchTint.secondary)
                if answered {
                    Label("Thanks. Take it easy today.", systemImage: "checkmark.circle.fill").scaledFont(14, .semibold).foregroundStyle(WatchTint.mood)
                } else {
                    HStack(spacing: 6) {
                        Button("Not great") { withAnimation(.snappy) { answered = true } }.tint(WatchTint.sick)
                        Button("I’m fine") { withAnimation(.snappy) { answered = true } }.tint(WatchTint.mood)
                    }
                    .scaledFont(14, .bold)
                }
                if let t = s.sickTonight { Text(t).scaledFont(13).foregroundStyle(WatchTint.secondary) }
            }
            .watchMargins()
        }
        .sensoryFeedback(.success, trigger: answered)
        .watchPage(tint: WatchTint.sick)
    }
}

// MARK: Shared pieces

/// The page's name in its color, where the system puts a title.
struct WatchHeader: View {
    var title: String
    var tint: Color
    var body: some View {
        Text(title).scaledFont(15, .semibold).foregroundStyle(tint).accessibilityAddTraits(.isHeader)
    }
}

/// A small tinted box with a label over a number.
struct WatchStat: View {
    var label: String
    var value: String
    var tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).scaledFont(12, .semibold).foregroundStyle(tint)
            Text(value).numberFont(18).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// An icon and a line of text in a soft capsule.
struct WatchPill: View {
    var icon: String
    var tint: Color
    var text: String
    var body: some View {
        Label {
            Text(text).scaledFont(13, .semibold).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The recovery ring with the score inside; the number ticks over when it changes.
struct WatchRing: View {
    var value: Int?
    var size: CGFloat
    var tint: Color = WatchTint.recovery

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: size * 0.13)
            Circle().trim(from: 0, to: CGFloat(value ?? 0) / 100)
                .stroke(AngularGradient(colors: [tint.opacity(0.7), tint], center: .center),
                        style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(value.map(String.init) ?? "–").font(.number(size * 0.38)).foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(value ?? 0)))
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: value)
        .accessibilityElement()
        .accessibilityLabel(value.map { "Recovery \($0)" } ?? "Recovery not ready")
    }
}

extension View {
    /// Keeps a page's content off the rounded edges of the screen, with room under the page dots.
    func watchMargins() -> some View {
        scenePadding(.horizontal)
            .padding(.bottom, 14)
    }

    /// A page's backdrop: its color glowing from one corner into black, as the system's own apps do.
    /// It's the page's container background, so the system cross-fades it as you scroll pages.
    func watchPage(tint: Color, at anchor: UnitPoint = .topLeading) -> some View {
        containerBackground(for: .tabView) {
            ZStack {
                Color.black
                RadialGradient(colors: [tint.opacity(0.55), tint.opacity(0.18), .clear], center: anchor, startRadius: 0, endRadius: 200)
            }
        }
        .foregroundStyle(.white)
    }
}
