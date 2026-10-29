import SwiftUI
import HealthCore

// "Late or missed a pill?" in two taps (H-A2): how many, and since when.
// The app knows her pack day, so the answer is for her pack week, at 11pm,
// not a table. The full rules stay one tap down (the guide article).

extension CycleCare {
    /// One answer for what she missed (CDC US SPR 2024), worded from the
    /// rules in `missedDoseRules(.combinedPill)`. `latest` is the pill to
    /// take now; `includesToday` when that's today's own pill.
    static func missedPillAnswer(_ advice: MissedPill.Advice, latest: Int, includesToday: Bool) -> (headline: String, steps: [String]) {
        switch advice.kind {
        case .breakPillsOnly:
            return ("Nothing to make up",
                    ["Those were break pills, with no hormones in them. Throw them out and start your next pack on time."])
        case .oneLate:
            let today = includesToday ? "Then keep going at your usual time." : "Take today\u{2019}s at your usual time, even if that means two today."
            return ("Take it now. You\u{2019}re covered.",
                    ["Take pill \(latest) now. \(today)", "No backup needed."])
        case .twoOrMore:
            var steps = ["Take pill \(latest) now (the latest one you missed) and skip the other missed ones. Then keep going at your usual time.",
                         "Use condoms, or don\u{2019}t have sex, until you\u{2019}ve taken 7 pills in a row."]
            if advice.skipBreak {
                steps.append("You missed in your last active week: skip the break and start the next pack straight after the active pills.")
            }
            if advice.emergencyWorthIt {
                steps.append("Missed in the first week and had sex in the last 5 days: ask a pharmacist about emergency contraception.")
            }
            return (advice.skipBreak ? "Skip the break and start the next pack" : "Take the latest one now. Condoms for 7 days.", steps)
        }
    }

    /// The emergency contraception options, one tap down.
    static let emergencyContraception = [
        "Levonorgestrel (Plan B and others): at any pharmacy, no prescription or ID. Best within 3 days of sex.",
        "Ella (ulipristal): needs a prescription, works up to 5 days after. Wait 5 days after it before your next pill, then use condoms for 7 days.",
        "A copper IUD put in within 5 days is the most effective, and then works as birth control.",
    ]
}

/// The helper: two questions and the answer under them, then the
/// emergency-contraception options and the full rules.
struct MissedPillHelper: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var twoOrMore: Bool?
    @State private var firstMissed: Date?

    /// A pill day she could have missed: midnight, and its pack day.
    private struct Choice: Hashable {
        var day: Date
        var packDay: Int
    }

    private var cal: Calendar { Calendar.current }

    /// The newest pill that's due: today's once her pill time has passed
    /// (or she's past midnight on it), else yesterday's.
    private var latestDue: Date {
        let today = model.currentPillDay
        let due = !cal.isDateInToday(today) || Clock.minutesOfDay(.now) >= model.pillTimeHere
        return due ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
    }

    /// The last 7 pill days up to the latest due, newest first.
    private var choices: [Choice] {
        guard let pack = model.pillPack else { return [] }
        return (0..<7).compactMap { back in
            cal.date(byAdding: .day, value: -back, to: latestDue).map { Choice(day: $0, packDay: pack.day(on: $0)) }
        }
    }

    /// For "two or more", the first one can't be the latest.
    private var shownChoices: [Choice] {
        let all = choices
        guard twoOrMore == true else { return Array(all.prefix(3)) }
        return Array(all.dropFirst())
    }

    /// The not-logged pill the app would guess she means.
    private var guess: Date? {
        guard !model.pillDoses.isEmpty else { return nil }
        let notLogged = choices.filter { $0.packDay <= (model.pillPack?.activeDays ?? 21) && !model.isPillTaken(on: $0.day) }
        // The oldest of the run of not-logged days ending at the latest due.
        var run: [Choice] = []
        for c in choices {
            guard notLogged.contains(c) else { break }
            run.append(c)
        }
        return run.count <= 3 ? run.last?.day : nil
    }

    var body: some View {
        Screen(title: "Missed or late pill?", accent: .yellow) {
            if let pack = model.pillPack {
                questions(pack)
                if let twoOrMore, let firstMissed, let first = choices.first(where: { cal.isDate($0.day, inSameDayAs: firstMissed) }) {
                    answer(pack, twoOrMore: twoOrMore, first: first)
                }
            }
            RowCard {
                ExpandRow(title: "Emergency contraception", summary: "Three options, from any pharmacy or clinic",
                          systemImage: "cross.vial.fill", accent: .coral) {
                    ForEach(CycleCare.emergencyContraception, id: \.self) { line in
                        bullet(line)
                    }
                }
            }
            if let article = GuideArticle.missedDose(for: .combinedPill) {
                LearnMoreRow("All the missed-pill rules", article: article, accent: .yellow)
            }
        }
        .onAppear {
            if firstMissed == nil { firstMissed = guess }
        }
    }

    private func questions(_ pack: PillPack) -> some View {
        Card {
            Text("How many did you miss?").font(.cardTitle)
            HStack(spacing: Space.s) {
                Chip(title: "One", selected: twoOrMore == false, accent: .yellow) { pick(two: false) }
                Chip(title: "Two or more", selected: twoOrMore == true, accent: .yellow) { pick(two: true) }
            }
            if twoOrMore != nil {
                Text(twoOrMore == true ? "Since when?" : "Which one?").font(.cardTitle)
                    .padding(.top, Space.s)
                FlowLayout(spacing: Space.s, lineSpacing: Space.s) {
                    ForEach(shownChoices, id: \.self) { c in
                        choiceChip(c)
                    }
                }
            }
        }
    }

    private func pick(two: Bool) {
        withMotion(.select) {
            twoOrMore = two
            if let f = firstMissed, !shownChoices.contains(where: { cal.isDate($0.day, inSameDayAs: f) }) { firstMissed = nil }
        }
    }

    /// "Pill 17 · yesterday", "Pill 15 · Mon", "Break · Sun".
    private func label(_ c: Choice) -> String {
        let pack = model.pillPack
        let name = c.packDay > (pack?.activeDays ?? 21) ? "Break pill" : "Pill \(c.packDay)"
        let when: String
        if cal.isDate(c.day, inSameDayAs: model.currentPillDay) { when = "today\u{2019}s" }
        else if let y = cal.date(byAdding: .day, value: -1, to: model.currentPillDay), cal.isDate(c.day, inSameDayAs: y) { when = "yesterday" }
        else { when = c.day.formatted(.dateTime.weekday(.abbreviated)) }
        return "\(name) \u{00B7} \(when)"
    }

    private func choiceChip(_ c: Choice) -> some View {
        let on = firstMissed.map { cal.isDate($0, inSameDayAs: c.day) } ?? false
        let p = Palette(scheme: scheme)
        let fill = scheme == .dark ? Accent.yellow.fill(.dark) : Accent.yellow.ink(.light)
        return Button {
            withMotion(.select) { firstMissed = c.day }
        } label: {
            Text(label(c))
                .font(.scaled(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: Sizes.minTap)
                .foregroundStyle(on ? (scheme == .dark ? Color(hex: 0x1A0E00) : .white) : p.primary)
                .background(on ? fill : p.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? fill : p.cardBorder))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func answer(_ pack: PillPack, twoOrMore: Bool, first: Choice) -> some View {
        let latest = choices.first ?? first
        let missed = twoOrMore
            ? MissedPill.span(from: first.packDay, through: latest.packDay, packLength: pack.packLength)
            : [first.packDay]
        let advice = MissedPill.advice(missedDays: missed, activeDays: pack.activeDays, packLength: pack.packLength)
        // The pill to take now: the latest active one she missed.
        let takeNow = twoOrMore ? (missed.last { $0 <= pack.activeDays } ?? latest.packDay) : first.packDay
        let isToday = cal.isDate(twoOrMore ? latest.day : first.day, inSameDayAs: model.currentPillDay)
        let words = CycleCare.missedPillAnswer(advice, latest: takeNow, includesToday: isToday)
        let accent: Accent = advice.kind == .twoOrMore ? .coral : .mint
        return Card(accent: accent) {
            Text(words.headline).font(.cardTitle)
                .foregroundStyle(accent.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(words.steps, id: \.self) { bullet($0) }
            Text(CycleCare.missedDoseSource)
                .font(.secondary).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .motionTransition(.reveal, edge: .top)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Accent.yellow.fill(scheme)).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
            Text(text).font(.bodyText).fixedSize(horizontal: false, vertical: true)
        }
    }
}
