import Combine
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    /// While the app is open, look at the calendar again every 30 minutes.
    private let calendarTimer = Timer.publish(every: 30 * 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch model.healthState {
            case .notConnected: ConnectView()
            case .unavailable: UnavailableView()
            default: tabs
            }
        }
        .tint(.mainText)
        .preferredColorScheme(.light)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await model.refreshHealth() }
            Task { await model.refreshCalendar() }
        }
        .onReceive(calendarTimer) { _ in Task { await model.refreshCalendar() } }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var tabs: some View {
        TabView {
            Tab("Today", systemImage: "house.fill") { NavigationStack { TodayView(showSettings: $showSettings) } }
            Tab("Sleep", systemImage: "moon.fill") { NavigationStack { SleepView() } }
            Tab("Body", systemImage: "heart.fill") { NavigationStack { BodyView() } }
            Tab("Exams", systemImage: "calendar") { NavigationStack { ExamsView(showSettings: $showSettings) } }
        }
    }
}

/// First launch: the Welcome screen from the canvas.
struct ConnectView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    Circle().stroke(Color.surface, lineWidth: 12).frame(width: 150, height: 150)
                    Circle().trim(from: 0, to: 0.72).stroke(Color.main, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 150, height: 150)
                    Image(systemName: "moon.stars.fill").font(.system(size: 44)).foregroundStyle(Color.mainText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                .accessibilityHidden(true)
                (Text("Your body, explained. ") + Text("Read from your Apple Watch.").italic().foregroundColor(.mainText))
                    .font(.serifTitle(36)).foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sleep, recovery, caffeine and your exam weeks, read straight from Apple Health. Nothing to export.")
                    .font(.system(size: 17)).foregroundStyle(Color(hex: 0x4A4F6E))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await model.connectHealth() }
                } label: {
                    Text("Connect Apple Health").font(.system(size: 18, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(.white)
                        .background(Color.ink, in: Capsule())
                }
                .padding(.top, 8)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(Color.mainText)
                    Text("**Your health data stays on your phone.** The app reads it here and never uploads it.")
                        .font(.system(size: 14)).foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.lavender)
    }
}

struct UnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash").font(.largeTitle).foregroundStyle(Color.muted)
            Text("Apple Health isn’t available on this device.").font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ground)
    }
}
