import SwiftUI

/// Vertical pages, as in the canvas: the getting-sick alert first when it's on, then Recovery,
/// Log, Tonight and Cycle. Tonight switches to dark after 8pm when that setting is on.
struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @State private var page = WatchRootView.startPage

    var body: some View {
        let s = store.snapshot
        TabView(selection: $page) {
            if s.sick { WatchSickView().tag("sick") }
            WatchRecoveryView().tag("recovery")
            WatchLogView().tag("log")
            WatchTonightView().tag("tonight")
            if s.cycleDay != nil && s.typicalLength != nil { WatchCycleView().tag("cycle") }
        }
        .tabViewStyle(.verticalPage)
        .onOpenURL { url in if url.host == "log" { page = "log" } }
    }

    /// Test builds can open a page directly with `-page tonight` (etc.).
    private static var startPage: String {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-page"), i + 1 < args.count { return args[i + 1] }
        #endif
        return WatchStore.shared.snapshot.sick ? "sick" : "recovery"
    }
}

private struct PageHeader: View {
    var title: String
    var color: Color
    var body: some View {
        HStack {
            Text(title).scaledFont(15, .bold).foregroundStyle(color)
            Spacer()
        }
    }
}

struct WatchRecoveryView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let s = store.snapshot
        ScrollView {
            VStack(spacing: 8) {
                PageHeader(title: "Recovery", color: .mainText)
                HStack(spacing: 10) {
                    WatchRing(value: s.recovery, size: 70, track: .surface)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.recoveryLabel.isEmpty ? "–" : s.recoveryLabel).numberFont(18).foregroundStyle(Color.ink)
                        Text(s.headline).scaledFont(13).foregroundStyle(Color(hex: 0x4A4F6E))
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color.lavender, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                HStack(spacing: 5) {
                    stat("HR", s.restingHr.map(String.init) ?? "–", s.hrUp ? .peach : .surface, s.hrUp ? .peachInk : .mainText)
                    stat("HRV", s.hrv.map(String.init) ?? "–", s.hrvDown ? .peach : .surface, s.hrvDown ? .peachInk : .mainText)
                    stat("Sleep", s.sleepMinutes.map { "\($0 / 60):\(String(format: "%02d", $0 % 60))" } ?? "–", .surface, .mainText)
                }
                if s.updated != .distantPast && !s.isFromToday {
                    Text("Yesterday’s numbers. Open the app on your iPhone to update.").scaledFont(12).foregroundStyle(Color.muted)
                }
                if s.updated == .distantPast {
                    Text("Open Health Dashboard on your iPhone to send today’s numbers.").scaledFont(12).foregroundStyle(Color.muted)
                }
            }
        }
        .watchPage(.ground)
    }

    private func stat(_ label: String, _ value: String, _ fill: Color, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).scaledFont(11, .bold).foregroundStyle(ink)
            Text(value).scaledFont(17, .bold).foregroundStyle(Color.ink).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct WatchLogView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let s = store.snapshot
        ScrollView {
            VStack(spacing: 8) {
                PageHeader(title: "Log", color: .butterInk)
                Button { Task { await store.logLatte() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cup.and.saucer.fill").scaledFont(26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Latte").numberFont(20)
                            Text("130 mg").scaledFont(13, .semibold)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color(hex: 0xFFE07A), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.saving)
                HStack(spacing: 6) {
                    small("+ Water · \(bottleOz(store.bottleMl))", .lavender) { await store.logWater() }
                    small("+ Drink", Color(hex: 0xF3E9FF)) { await store.logDrink() }
                }
                HStack {
                    Text("Today \(Int(s.caffeineToday)) mg").foregroundStyle(Color(hex: 0x4A4F6E))
                    Spacer()
                    Text("Cutoff 2pm").fontWeight(.bold).foregroundStyle(Color.butterInk)
                }
                .scaledFont(12)
                if let msg = store.lastLogged { Text(msg).scaledFont(12, .bold).foregroundStyle(Color.mintInk) }
            }
        }
        .watchPage(.ground)
    }

    private func bottleOz(_ ml: Double) -> String { "\(Int((ml / 29.5735).rounded())) oz" }

    private func small(_ title: String, _ fill: Color, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).scaledFont(15, .bold).foregroundStyle(Color.ink).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44).background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.saving)
    }
}

struct WatchTonightView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let s = store.snapshot
        let hour = Calendar.current.component(.hour, from: .now)
        let dark = s.darkAtNight && (hour >= 20 || hour < 6)
        let minutesNow = (hour < 18 ? hour + 24 : hour) * 60 + Calendar.current.component(.minute, from: .now) - 18 * 60
        let pastBedtime = s.bedtimeMinutes.map { dark && minutesNow > $0 } ?? false
        ScrollView {
            VStack(spacing: 8) {
                PageHeader(title: "Tonight", color: dark ? Color(hex: 0x9AA6FA) : .mainText)
                VStack(alignment: .leading, spacing: 0) {
                    Text(pastBedtime ? "You’re up past" : "Asleep by").scaledFont(13).foregroundStyle(dark ? Color(hex: 0xB9BCD4) : Color(hex: 0x4A4F6E))
                    Text(s.bedBy?.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "") ?? "–")
                        .numberFont(40).foregroundStyle(dark ? .white : Color.ink)
                    Text(pastBedtime ? "Asleep soon still gets you a good night" : "8 hours before morning class")
                        .scaledFont(12).foregroundStyle(dark ? Color(hex: 0xB9BCD4) : Color(hex: 0x4A4F6E))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(dark ? Color(hex: 0x15172B) : Color.lavender, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                if let note = s.examNote {
                    Label(note, systemImage: "calendar").scaledFont(13, .semibold)
                        .foregroundStyle(dark ? Color(hex: 0xD8DAEA) : Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(dark ? Color(hex: 0x15172B) : Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                HStack {
                    if let p = s.phase { Text(p) }
                    Spacer()
                    if let c = s.caffeineAtBed { Text("Caffeine ~\(Int(c.rounded())) mg") }
                }
                .scaledFont(12).foregroundStyle(dark ? Color(hex: 0xB9BCD4) : Color(hex: 0x4A4F6E))
            }
        }
        .watchPage(dark ? .black : .ground)
    }
}

struct WatchCycleView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let s = store.snapshot
        ScrollView {
            VStack(spacing: 8) {
                PageHeader(title: "Cycle", color: .mainText)
                HStack(spacing: 10) {
                    PhaseRing(day: s.cycleDay ?? 1, length: s.typicalLength ?? 28, periodLength: s.periodLength ?? 5, ovulation: s.ovulationDay ?? 14)
                        .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.phase ?? "").numberFont(18).foregroundStyle(Color.ink)
                        if let d = s.daysToPeriod, d >= 0 { Text("Period ~\(d) days").scaledFont(12).foregroundStyle(Color(hex: 0x4A4F6E)) }
                        if let t = s.tempDelta { Text("Temp \(t >= 0 ? "+" : "")\(String(format: "%.1f", t))°C").scaledFont(12, .bold).foregroundStyle(Color.peachInk) }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Recovery").scaledFont(11, .bold).foregroundStyle(Color.mainText)
                        Text(s.recovery.map(String.init) ?? "–").scaledFont(20, .bold).foregroundStyle(Color.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    .background(Color.lavender, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button { Task { await store.logLatte() } } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Tap to log").scaledFont(11, .bold)
                            Text("Latte").scaledFont(20, .bold)
                        }
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(Color(hex: 0xFFE07A), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .watchPage(.ground)
    }
}

/// The cycle as a ring of phase colors, with a dot on today.
struct PhaseRing: View {
    var day: Int, length: Int, periodLength: Int, ovulation: Int

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line = size * 0.14
            ZStack {
                segment(1, periodLength, Color(hex: 0xF07A6B), line)
                segment(periodLength + 1, ovulation - 2, Color(hex: 0xFFD2BD), line)
                segment(ovulation - 1, ovulation + 1, Color(hex: 0x5B6BE8), line)
                segment(ovulation + 2, length, Color(hex: 0xC9CFFF), line)
                let angle = (Double(day) - 0.5) / Double(length) * 2 * .pi - .pi / 2
                Circle().fill(Color.ink).overlay(Circle().stroke(Color.ground, lineWidth: 2))
                    .frame(width: line * 1.3, height: line * 1.3)
                    .offset(x: cos(angle) * (size - line) / 2, y: sin(angle) * (size - line) / 2)
                Text("\(day)").font(.number(size * 0.3)).foregroundStyle(Color.ink)
            }
            .frame(width: size, height: size)
        }
        .accessibilityElement()
        .accessibilityLabel("Cycle day \(day)")
    }

    private func segment(_ from: Int, _ to: Int, _ color: Color, _ line: CGFloat) -> some View {
        Circle()
            .trim(from: CGFloat(from - 1) / CGFloat(length) + 0.004, to: CGFloat(max(from, to)) / CGFloat(length) - 0.004)
            .stroke(color, lineWidth: line)
            .rotationEffect(.degrees(-90))
            .padding(line / 2)
    }
}

struct WatchSickView: View {
    @Environment(WatchStore.self) private var store
    @State private var answered = false

    var body: some View {
        let s = store.snapshot
        ScrollView {
            VStack(spacing: 8) {
                PageHeader(title: "Heads up", color: .peachInk)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Body working harder").numberFont(18).foregroundStyle(Color.ink)
                    Text("Bug coming on, or stress? Just a guess.").scaledFont(13).foregroundStyle(Color(hex: 0x4A4F6E))
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(Color.peach, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                if answered {
                    Text("Thanks. Take it easy today.").scaledFont(13, .bold).foregroundStyle(Color.mintInk)
                } else {
                    HStack(spacing: 6) {
                        Button { answered = true } label: {
                            Text("Not great").scaledFont(14, .bold).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 44).background(Color.ink, in: Capsule())
                        }
                        Button { answered = true } label: {
                            Text("I feel fine").scaledFont(14, .bold).foregroundStyle(Color.mintInk)
                                .frame(maxWidth: .infinity, minHeight: 44).background(Color.mint, in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let t = s.sickTonight { Text(t).scaledFont(12).foregroundStyle(Color(hex: 0x4A4F6E)) }
            }
        }
        .watchPage(.ground)
    }
}

struct WatchRing: View {
    var value: Int?
    var size: CGFloat
    var track: Color = .lavender
    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: size * 0.13)
            Circle().trim(from: 0, to: CGFloat(value ?? 0) / 100)
                .stroke(Color.main, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(value.map(String.init) ?? "–").font(.number(size * 0.32)).foregroundStyle(Color.ink)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(value.map { "Recovery \($0)" } ?? "Recovery not ready")
    }
}

extension View {
    /// The canvas's Watch screens are light (dark only at night), so paint the page color
    /// edge to edge instead of using the system's dark Watch background.
    func watchPage(_ color: Color) -> some View {
        containerBackground(color, for: .tabView)
            .background(color.ignoresSafeArea())
    }
}
