import SwiftUI

/// Pieces of the Glow look (the Watch's style on the iPhone): small dials, the sleep dial, and the
/// cards built from them. The Light look keeps the original layouts.

/// A small dial for one of today's numbers: the dot sits mid-way on a normal day and swings either way.
struct GaugeCell: View {
    var label: String
    var value: String
    /// 0…1 along the dial; 0.5 is her normal.
    var position: Double
    var tint: Color
    var change: String?
    /// Worse than her normal: the change shows in peach, as the Light look does.
    var worse = false
    /// In its own tinted pane (Recovery) or bare (inside the Today card).
    var boxed = false

    var body: some View {
        VStack(spacing: 4) {
            Gauge(value: min(1, max(0, position))) {
                EmptyView()
            } currentValueLabel: {
                Text(value).font(.number(16)).contentTransition(.numericText())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [tint.opacity(0.55), tint]))
            .scaleEffect(1.1)
            .padding(.vertical, 4)
            Text(label).scaledFont(13, .bold).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.8)
            if let change {
                Text(change).scaledFont(12, worse ? .bold : .semibold).foregroundStyle(worse ? Color.peachInk : Color.muted2)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, boxed ? 12 : 0)
        .padding(.horizontal, boxed ? 6 : 0)
        .background(boxed ? tint.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Today's resting HR, HRV and sleep as three dials, each against her normal.
struct RecoveryGauges: View {
    @Environment(AppModel.self) private var model
    var boxed = false

    var body: some View {
        let r = model.recoveryToday
        let hrv = model.health.hrv[model.today], rhr = model.health.restingHr[model.today]
        HStack(spacing: boxed ? 8 : 6) {
            // Every dial leans right when that number is better than normal: higher HRV, lower
            // resting heart rate, more sleep.
            GaugeCell(label: "HRV", value: hrv.map { "\(Int($0.rounded()))" } ?? "–", position: 0.5 + (r?.hrvChange ?? 0) * 2.5,
                      tint: Color(hex: 0xFF9A7A), change: r?.hrvChange.map { signedPercent($0) },
                      worse: (r?.hrvChange ?? 0) <= -0.1, boxed: boxed)
            GaugeCell(label: "Resting HR", value: rhr.map { "\(Int($0.rounded()))" } ?? "–", position: 0.5 - (r?.restingHrChange ?? 0) / 10,
                      tint: Color(hex: 0xFF6B8A), change: r?.restingHrChange.map { signedWhole($0, " bpm") },
                      worse: (r?.restingHrChange ?? 0) >= 3, boxed: boxed)
            GaugeCell(label: "Sleep", value: model.lastNight.map { String(format: "%.1fh", Double($0.asleepMinutes) / 60) } ?? "–",
                      position: Double(model.lastNight?.asleepMinutes ?? 0) / 540, tint: Color(hex: 0x5EE0C1),
                      change: r?.sleepChange.map { abs($0) < 15 ? "typical" : "\($0 > 0 ? "+" : "−")\(hoursMinutes(abs($0)))" },
                      worse: (r?.sleepChange ?? 0) <= -45, boxed: boxed)
        }
    }

    private func signedPercent(_ x: Double) -> String {
        let n = Int((x * 100).rounded())
        return n == 0 ? "normal" : "\(n > 0 ? "+" : "−")\(abs(n))%"
    }

    private func signedWhole(_ x: Double, _ unit: String) -> String {
        let n = Int(x.rounded())
        return n == 0 ? "normal" : "\(n > 0 ? "+" : "−")\(abs(n))\(unit)"
    }
}

/// A 12-hour clock with a night drawn as an arc from falling asleep (moon) to waking (sun).
struct SleepDialView<Center: View>: View {
    /// Falling asleep, in minutes after 6pm, and how long, in minutes.
    var start: Int
    var minutes: Int
    @ViewBuilder var center: Center

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line = size * 0.11
            let from = Double((start + 18 * 60) % 720) / 720
            let length = min(1, Double(minutes) / 720)
            let radius = (size - line) / 2
            ZStack {
                Circle().stroke(Color.track, lineWidth: line)
                Circle()
                    .trim(from: 0, to: length)
                    .stroke(AngularGradient(colors: [Color(hex: 0x9B86FF), Color(hex: 0xFFA94D)], center: .center,
                                            startAngle: .zero, endAngle: .degrees(length * 360)),
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(from * 360 - 90))
                ForEach([(0, "12"), (3, "3"), (6, "6"), (9, "9")], id: \.0) { hour, label in
                    let angle = Double(hour) / 12 * 2 * .pi - .pi / 2
                    Text(label).font(.system(size: max(9, size * 0.065), weight: .semibold)).foregroundStyle(Color.muted.opacity(0.7))
                        .offset(x: cos(angle) * (radius - line * 1.5), y: sin(angle) * (radius - line * 1.5))
                }
                endpoint("moon.fill", Color(hex: 0xC7B8FF), at: from, radius: radius, line: line)
                endpoint("sun.max.fill", Color(hex: 0xFFA94D), at: from + length, radius: radius, line: line)
                center
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func endpoint(_ icon: String, _ tint: Color, at fraction: Double, radius: CGFloat, line: CGFloat) -> some View {
        let angle = fraction * 2 * .pi - .pi / 2
        return Image(systemName: icon)
            .font(.system(size: line * 0.62, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: line * 1.35, height: line * 1.35)
            .background(Color(hex: 0x1A1245), in: Circle())
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
    }
}

/// Today's "Tonight" card: the planned night on a dial, bed and wake times, and the smart alarm.
struct TonightCard: View {
    @Environment(AppModel.self) private var model
    @State private var link = AlarmLink.shared

    var body: some View {
        let bed = model.bedtimeTarget
        HStack(spacing: 14) {
            SleepDialView(start: bed, minutes: 8 * 60) {
                Text("8h").numberFont(20).foregroundStyle(Color.ink)
            }
            .frame(width: 88, height: 88)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("TONIGHT").labelFont().foregroundStyle(Color(hex: 0xC7B8FF))
                // "Up" is the smart alarm's time when there is one, so the card never shows two.
                Text("Bed by \(clockTime(Double(bed))), up \(link.plan?.latestText ?? clockTime(Double(bed + 8 * 60)))")
                    .scaledFont(17, .bold).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                Label(alarmText, systemImage: "alarm.fill")
                    .scaledFont(13, .semibold).foregroundStyle(Color.ink)
                    .padding(.horizontal, 10).frame(minHeight: 30)
                    .background(Color(hex: 0xFFA94D).opacity(0.2), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color(hex: 0x9B86FF).opacity(0.14), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color(hex: 0x9B86FF).opacity(0.2)))
        .accessibilityElement(children: .combine)
    }

    private var alarmText: String {
        guard link.plan != nil else { return "Smart alarm off" }
        return switch link.watchStatus?.state {
        case .armed where link.watchStatus?.isSet == true: "Smart alarm on"
        case .failed: "Smart alarm not set"
        case .waiting, .armed: "Smart alarm: open Watch app"
        default: WatchSync.shared.watchReady ? "Smart alarm: sending" : "Smart alarm needs the Watch app"
        }
    }
}

/// Sleep's top card in Glow: last night on the dial, with when she fell asleep, woke, and regularity.
struct LastNightCard: View {
    var night: Night
    var regularity: Int?

    var body: some View {
        HStack(spacing: 16) {
            SleepDialView(start: night.bedtime, minutes: night.wake - night.bedtime) {
                VStack(spacing: 2) {
                    Text(hoursMinutes(Double(night.asleepMinutes))).numberFont(24).foregroundStyle(Color.ink)
                    Text("last night").scaledFont(11, .semibold).foregroundStyle(Color.muted)
                }
            }
            .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 10) {
                stat("ASLEEP", clockTime(Double(night.bedtime)), Color(hex: 0xC7B8FF))
                stat("AWAKE", clockTime(Double(night.wake)), Color(hex: 0xFFA94D))
                if let regularity { stat("REGULARITY", "\(regularity)", Color(hex: 0x5EE0C1)) }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last night: asleep \(clockTime(Double(night.bedtime))), awake \(clockTime(Double(night.wake))), \(hoursMinutes(Double(night.asleepMinutes))) of sleep")
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).labelFont().foregroundStyle(tint)
            Text(value).numberFont(20).foregroundStyle(Color.ink)
        }
    }
}
