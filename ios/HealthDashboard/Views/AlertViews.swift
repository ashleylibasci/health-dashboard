import SwiftUI

struct SickView: View {
    @Environment(AppModel.self) private var model
    @State private var logged: Set<Symptom> = []
    @State private var feelFine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("This is a guess, not a diagnosis. It can be wrong.", systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.butter, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            (Text("Your body’s working ") + Text("harder than usual").italic().foregroundColor(.peachInk))
                .font(.serifTitle(34)).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
            Text("For two mornings, several signals moved together. That can happen a day or two before a cold. It can also be stress, a late night, or nothing at all.")
                .font(.system(size: 16)).foregroundStyle(Color(hex: 0x4A4F6E)).fixedSize(horizontal: false, vertical: true)
            if let s = model.sick {
                Card {
                    HStack { CardLabel("What we noticed", color: .muted); Spacer(); Pill(text: s.confidence, fill: .peach, ink: .peachInk) }
                    if let v = s.restingHr { ValueRow(label: "Resting heart rate", value: "\(signed(v, " bpm")) · 2 mornings", valueColor: .peachInk) }
                    if let v = s.hrv { ValueRow(label: "HRV", value: "\(signed(v * 100, ""))%", valueColor: .peachInk) }
                    if let v = s.temperature { ValueRow(label: "Wrist temperature", value: "+\(String(format: "%.1f", v))°\(model.cycle?.phase == .luteal ? " beyond cycle" : "")", valueColor: .peachInk) }
                    if let v = s.breathing { ValueRow(label: "Breathing rate", value: "\(signed(v, "")) / min", valueColor: .peachInk) }
                    if model.cycle?.phase == .luteal {
                        Label("Already adjusted for your luteal phase, which raises temperature on its own.", systemImage: "circle.fill")
                            .font(.system(size: 14)).foregroundStyle(Color(hex: 0x4A4F6E)).padding(10)
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
                            logged.insert(s)
                            Task { await model.logSymptom(s) }
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
                Text("When to see a doctor").font(.system(size: 15, weight: .bold))
                Text("Fever over 100.4°F, trouble breathing, or feeling worse after 3 days: contact McKinley Health Center or your doctor.").font(.system(size: 14)).foregroundStyle(Color(hex: 0x4A4F6E))
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
            Text("Your top reasons, ranked by how far each one is from your normal.").font(.system(size: 15)).foregroundStyle(Color.muted)
            let reasons = model.reasons
            if reasons.isEmpty {
                Card(fill: .mint) { Note("Nothing in your data stands out today. Sometimes a day is just a day.") }
            }
            ForEach(Array(reasons.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 14) {
                    Text("\(i + 1)").font(.number(18)).foregroundStyle(ink(r.kind))
                        .frame(width: 40, height: 40).background(fill(r.kind), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                        Text(r.detail).font(.system(size: 14)).foregroundStyle(Color(hex: 0x4A4F6E)).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            if !reasons.isEmpty {
                Card(fill: .lavender) {
                    CardLabel("The one thing to do")
                    Text(oneThing(for: reasons, bedtime: clockTime(Double(model.bedtimeTarget)))).font(.system(size: 16)).foregroundStyle(Color.ink)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Does this match how you feel?").font(.system(size: 14, weight: .bold))
                    if let a = answered {
                        Text(a ? "Thanks. Look after yourself today." : "Thanks. Some days the data can’t see what’s going on.").font(.system(size: 15)).foregroundStyle(Color.muted)
                    } else {
                        HStack(spacing: 10) {
                            Button("Yes, that’s it") { answered = true }
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.mintInk)
                                .frame(maxWidth: .infinity, minHeight: 48).background(Color.mint, in: Capsule())
                            Button("Not really") { answered = false }
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
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
        switch k { case .body, .lateNight: .peach; case .caffeine, .exam: .butter; case .cycle: Color(hex: 0xE4E7FF); case .drinks: Color(hex: 0xF3E9FF); default: .lavender }
    }
    private func ink(_ k: OffReason.Kind) -> Color {
        switch k { case .body, .lateNight: .peachInk; case .caffeine, .exam: .butterInk; case .drinks: Color(hex: 0x7A3FC2); default: .mainText }
    }
}

struct StreaksView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.streakInfo
        let all = badges(model.health, recovery: model.recovery, exams: model.exams, streaks: s)
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Streaks ", accent: "and wins")
            HStack(spacing: 10) {
                streakTile("\(s.bedtimeNights)", "nights in bed by \(clockTime(Double(s.bedtimeTarget)))", .lavender, .mainText)
                streakTile("\(s.caffeineDays)", "days of caffeine logs", .butter, .butterInk)
                streakTile("\(s.waterDays)", "days hitting water goal", .mint, .mintInk)
            }
            Card {
                HStack { CardLabel("Earned", color: .muted); Spacer(); Text("\(all.filter(\.earned).count) of \(all.count)").font(.system(size: 14, weight: .bold)) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                    ForEach(all) { b in
                        VStack(spacing: 6) {
                            Image(systemName: b.symbol).font(.system(size: 24)).foregroundStyle(b.earned ? Color.mainText : Color(hex: 0xA3A6B8))
                                .frame(width: 60, height: 60).background(b.earned ? Color.lavender : Color.track, in: Circle())
                            Text(b.name).font(.system(size: 12, weight: .bold)).foregroundStyle(b.earned ? Color.ink : Color(hex: 0x7A7E95)).multilineTextAlignment(.center)
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
            Text(value).font(.number(30)).foregroundStyle(Color.ink)
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(ink).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 8)
        .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
