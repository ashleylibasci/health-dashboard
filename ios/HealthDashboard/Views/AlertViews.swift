import SwiftUI

struct SickView: View {
    @Environment(AppModel.self) private var model
    @State private var logged: Set<Symptom> = []
    @State private var feelFine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("This is a guess, not a diagnosis. It can be wrong.", systemImage: "exclamationmark.circle.fill")
                .scaledFont(14, .semibold).foregroundStyle(Color.ink)
                .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.butter, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            (Text("Your body’s working ") + Text("harder than usual").italic().foregroundColor(.peachInk))
                .serifTitleFont(34).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
            Text("For two mornings, several signals moved together. That can happen a day or two before a cold. It can also be stress, a late night, or nothing at all.")
                .scaledFont(16).foregroundStyle(Color.muted2).fixedSize(horizontal: false, vertical: true)
            if let s = model.sick {
                Card {
                    AdaptiveStack { CardLabel("What we noticed", color: .muted); Spacer(minLength: 0); Pill(text: s.confidence, fill: .peach, ink: .peachInk) }
                    if let v = s.restingHr { ValueRow(label: "Resting heart rate", value: "\(signed(v, " bpm")) · 2 mornings", valueColor: .peachInk) }
                    if let v = s.hrv { ValueRow(label: "HRV", value: "\(signed(v * 100, ""))%", valueColor: .peachInk) }
                    if let v = s.temperature { ValueRow(label: "Wrist temperature", value: "+\(String(format: "%.1f", v)) °C\(model.cycle?.phase == .luteal ? " beyond cycle" : "")", valueColor: .peachInk) }
                    if let v = s.breathing { ValueRow(label: "Breathing rate", value: "\(signed(v, "")) / min", valueColor: .peachInk) }
                    if model.cycle?.phase == .luteal {
                        Label("Already adjusted for your luteal phase, which raises temperature on its own.", systemImage: "circle.fill")
                            .scaledFont(14).foregroundStyle(Color.muted2).padding(10)
                            .background(Color.lavender, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            } else {
                Card(fill: .mint) { Note("Your signals look like your normal right now.") }
            }
            VStack(alignment: .leading, spacing: 10) {
                CardLabel("Feeling anything? Log it", color: .muted)
                FlowLayout {
                    ForEach(Symptom.cold) { s in
                        Chip(text: s.rawValue, selected: logged.contains(s), selectedFill: .peach) {
                            guard !logged.contains(s) else { return }
                            // Only light up once Health actually saved it.
                            Task { if await model.logSymptom(s) { logged.insert(s) } }
                        }
                    }
                    Chip(text: "I feel fine", selected: feelFine, selectedFill: .mint) { feelFine = true }
                }
                Note("Symptoms are saved to Apple Health.")
            }
            Card(fill: .mint) {
                CardLabel("Things that may help", color: .mintInk)
                Bullet("Sleep early tonight. Aim for 9 hours.")
                Bullet("Extra water, and skip drinks for a few days.")
                Bullet("Swap today’s workout for a walk.")
                Bullet("Some people take vitamin C or zinc at the first sign of a cold. Evidence that it helps is mixed, so ask a pharmacist first.")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("When to see a doctor").scaledFont(15, .bold)
                Text("Fever over 100.4 °F (38 °C), trouble breathing, or feeling worse after 3 days: contact McKinley Health Center or your doctor.").scaledFont(14).foregroundStyle(Color.muted2)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(hex: 0xFFD2BD), lineWidth: 2))
            Note("This looks for patterns in your Apple Watch data. It is not a medical device, cannot diagnose illness, and may miss things or flag you when you’re fine.")
        }
        .detailPage()
    }
}

struct WhyOffView: View {
    @Environment(AppModel.self) private var model
    @State private var answered: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Why you might ", accent: "feel off", after: " today")
            Text("Your top reasons, ranked by how far each one is from your normal.").scaledFont(15).foregroundStyle(Color.muted)
            let reasons = model.reasons
            if reasons.isEmpty {
                Card(fill: .mint) { Note("Nothing in your data stands out today. Sometimes a day is just a day.") }
            }
            ForEach(Array(reasons.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 0) {
                    AdaptiveStack(spacing: 14) {
                        Text("\(i + 1)").numberFont(18).foregroundStyle(ink(r.kind)).limitedTextGrowth()
                            .frame(width: 40, height: 40).background(fill(r.kind), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).scaledFont(16, .bold).foregroundStyle(Color.ink)
                            Text(r.detail).scaledFont(14).foregroundStyle(Color.muted2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            if !reasons.isEmpty {
                Card(fill: .lavender) {
                    CardLabel("The one thing to do")
                    Text(oneThing(for: reasons, bedtime: clockTime(Double(model.bedtimeTarget)))).scaledFont(16).foregroundStyle(Color.ink)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Does this match how you feel?").scaledFont(14, .bold)
                    if let a = answered {
                        Text(a ? "Thanks. Look after yourself today." : "Thanks. Some days the data can’t see what’s going on.").scaledFont(15).foregroundStyle(Color.muted)
                    } else {
                        AdaptiveStack(spacing: 10) {
                            Button("Yes, that’s it") { answered = true }
                                .scaledFont(15, .bold).foregroundStyle(Color.mintInk)
                                .frame(maxWidth: .infinity, minHeight: 48).background(Color.mint, in: Capsule())
                            Button("Not really") { answered = false }
                                .scaledFont(15, .bold).foregroundStyle(Color.ink)
                                .frame(maxWidth: .infinity, minHeight: 48).background(Color.surface, in: Capsule())
                        }
                    }
                }
            }
            Note("Best guesses from your own data, not medical advice.")
        }
        .detailPage()
    }

    private func fill(_ k: OffReason.Kind) -> Color {
        switch k { case .body, .lateNight: .peach; case .caffeine, .exam: .butter; case .cycle: Color.periwinkle; case .drinks: Color.lilac; default: .lavender }
    }
    private func ink(_ k: OffReason.Kind) -> Color {
        switch k { case .body, .lateNight: .peachInk; case .caffeine, .exam: .butterInk; case .drinks: Color.lilacInk; default: .mainText }
    }
}

struct StreaksView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.streakInfo
        let all = badges(model.health, recovery: model.recovery, exams: model.exams, streaks: s)
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Streaks ", accent: "and wins")
            AdaptiveStack(spacing: 10) {
                streakTile("\(s.bedtimeNights)", "nights in bed by \(clockTime(Double(s.bedtimeTarget)))", .lavender, .mainText)
                streakTile("\(s.caffeineDays)", "days of caffeine logs", .butter, .butterInk)
                streakTile("\(s.waterDays)", "days hitting water goal", .mint, .mintInk)
            }
            Card {
                AdaptiveStack { CardLabel("Earned", color: .muted); Spacer(minLength: 0); Text("\(all.filter(\.earned).count) of \(all.count)").scaledFont(14, .bold) }
                AdaptiveGrid(columns: 3, accessibilityColumns: 2, spacing: 12, rowSpacing: 14) {
                    ForEach(all) { b in
                        VStack(spacing: 6) {
                            Image(systemName: b.symbol).scaledFont(24).foregroundStyle(b.earned ? Color.mainText : Color.muted).limitedTextGrowth()
                                .frame(width: 60, height: 60).background(b.earned ? Color.lavender : Color.track, in: Circle())
                            Text(b.name).scaledFont(12, .bold).foregroundStyle(b.earned ? Color.ink : Color.muted).multilineTextAlignment(.center)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(b.name), \(b.earned ? "earned" : "not yet: \(b.detail)")")
                    }
                }
            }
            let test = cutoffTest(model.health.caffeineLogs, nights: model.health.nights)
            if !test.isReady {
                Card(fill: .lavender) {
                    CardLabel("Next up")
                    ValueRow(label: "Caffeine scientist", value: "\(test.daysLogged) / 21 days")
                    Meter(value: Double(test.daysLogged) / 21, track: .surface)
                    Note("Unlocks your personal caffeine cutoff time.")
                }
            }
            Note("Streaks stay on your phone. Sharing with friends isn’t built yet.")
        }
        .detailPage()
    }

    private func streakTile(_ value: String, _ label: String, _ fill: Color, _ ink: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).numberFont(30).foregroundStyle(Color.ink)
            Text(label).scaledFont(12, .bold).foregroundStyle(ink).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 8)
        .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
