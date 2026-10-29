import SwiftUI
import HealthCore

// Bleeding care lines, missed pills and medicines that affect birth control.
// One wording for each, used by the Cycle, Log and Learn screens, so the
// same question never gets two different answers (women's health review).

/// Care thresholds and safety lines, in plain words.
enum CycleCare {
    /// ACOG's signs of heavy menstrual bleeding (Okafor H).
    static let heavyBleeding = "Very heavy bleeding means soaking through a pad or tampon every hour for several hours in a row, needing two at once, passing clots the size of a quarter or bigger, or bleeding for more than 7 days. Worth a call to a doctor."
    /// The urgent tier for heavy bleeding.
    static let heavyBleedingUrgent = "Heavy bleeding and feeling dizzy, faint or short of breath, or a racing heart? Get care today."

    /// Bleeding that needs checking on the implant, shot or an IUD (Okafor F).
    static let bleedingRedFlags = "New bleeding after sex, bleeding with pelvic pain, fever or unusual discharge, or a sudden change from your settled pattern: see a clinician for an STI and pregnancy test."

    /// No period for 90 days on a natural cycle (Okafor E, Ruiz F1, ACOG CO 651).
    static let noPeriodThreeMonths = "Three months without a period is worth seeing a clinician about. Pregnancy, not eating enough for your training, thyroid or prolactin changes and PCOS are common causes, and all of them can be checked."

    /// Under-fuelling (RED-S), for late or missing periods (Ruiz F1, IOC 2023).
    static let redS = "If you\u{2019}ve been training harder, eating less or losing weight, a late or missing period can mean your body isn\u{2019}t getting enough fuel (RED-S). It affects your bones, so see campus health or sports medicine."

    /// A withdrawal bleed can't show under-fuelling (Ruiz F2).
    static let packBleedCantShowFuel = "Your break-week bleed comes from your birth control, so it can\u{2019}t show whether you\u{2019}re eating enough for your training. Watch for tiredness, frequent injuries, bone pain or getting ill often."
    /// The same caveat for methods that change bleeding without a break.
    static let methodBleedCantShowFuel = "Your bleeding pattern comes from your birth control, so it can\u{2019}t show whether you\u{2019}re eating enough for your training. Watch for tiredness, frequent injuries, bone pain or getting ill often."

    /// When a home test can be trusted, and when to repeat it (Okafor N).
    static let pregnancyTestTiming = "A home test is reliable from the day your period was due. If it\u{2019}s negative and your period still hasn\u{2019}t come, test again in a week. With irregular or no periods, test 3 weeks after sex."

    /// No bleed in the break after a missed or late pill, ring or patch
    /// (Shah F3, Okafor A; CDC US SPR 2024): never wait to start the next one.
    static func noBleedAdvice(_ method: BirthControl) -> String {
        let thing: String
        let next: String
        switch method {
        case .ring: thing = "your ring"; next = "Put in your next ring on time."
        case .patch: thing = "a patch"; next = "Start your next patch on time."
        default: thing = "a pill"; next = "Start your next pack on time."
        }
        return "Missed or late with \(thing) and no bleed in the break? \(next) Take a pregnancy test now, and again in 3 weeks if you had sex in the last 3 weeks. Sex in the last 5 days? Ask a pharmacist about emergency contraception."
    }

    /// Starting a new pack, ring or patch 2 or more days late (Okafor B).
    static func lateStartWarning(_ method: BirthControl) -> String {
        let what = method == .ring ? "Put in 2 or more days late" : "Started 2 or more days late"
        return "\(what): use condoms for the next 7 days. Had sex in the last 5 days? Emergency contraception may be worth it. Ask a pharmacist."
    }

    /// New low mood on a hormonal method (Laurent F8).
    static let moodOnHormones = "New low mood or anxiety in the first months on it? Tell your prescriber. Another method may suit you better."
}

// MARK: - Missed, late or sick

extension CycleCare {
    /// Methods with a pill, ring or patch to miss or be late with.
    static let missedDoseMethods: [BirthControl] = [.combinedPill, .miniPill, .ring, .patch]

    /// "Missed or late pill?", "Ring out, or put in late?"…
    static func missedDoseTitle(_ method: BirthControl) -> String {
        switch method {
        case .ring: "Ring out, or put in late?"
        case .patch: "Patch off, or put on late?"
        default: "Missed or late pill?"
        }
    }

    /// What to do when it's missed or late (CDC US SPR 2024; Okafor A, D;
    /// Shah F4). Empty for methods with nothing to miss day to day.
    static func missedDoseRules(_ method: BirthControl) -> [String] {
        switch method {
        case .combinedPill:
            return ["Up to a day late, or one pill missed: take it now, even if that means two today. Keep going. No backup needed.",
                    "Two or more missed in a row: take the latest one now and skip the others. Use condoms for 7 days.",
                    "Missed in your last active week: skip the break and start the next pack straight after the active pills.",
                    "Missed in the first week and had sex in the last 5 days: ask a pharmacist about emergency contraception.",
                    "Vomiting or diarrhea: under 48 hours, no extra pill. 48 hours or more, keep taking pills and use condoms until you\u{2019}ve had 7 days of pills after it stops."]
        case .miniPill:
            return ["Most mini pills (norethindrone or norgestrel, like Opill): more than 3 hours late, take one now and keep going. Use condoms for the next 2 days.",
                    "Vomiting within 3 hours of a pill: take another one.",
                    "Drospirenone mini pill (Slynd): up to a day late is fine. Take it now. Two or more missed in a row: take one now and use condoms for 7 days.",
                    "Late or missed and had sex recently: ask a pharmacist about emergency contraception."]
        case .ring:
            return ["Out, or put in late, under 48 hours: put it back (or a new one) in now. No backup needed.",
                    "48 hours or more: put it in now and use condoms for 7 days. If this was in week 3, skip the ring-free week and start a new ring.",
                    "Put a new ring in late and had sex in the last 5 days: ask a pharmacist about emergency contraception."]
        case .patch:
            return ["Off, or put on late, under 48 hours: put a new one on now and keep your usual change day. No backup needed.",
                    "48 hours or more: put one on now and use condoms for 7 days. If this was in week 3, skip the patch-free week and start a new patch.",
                    "Started a new patch late and had sex in the last 5 days: ask a pharmacist about emergency contraception."]
        default:
            return []
        }
    }

    static let missedDoseSource = "From the CDC\u{2019}s 2024 guidance. Not sure? A pharmacist can tell you what to do, no appointment needed."

    /// Methods some medicines make work less well (Shah F4). Nothing for
    /// IUDs or the shot.
    static let medicineMethods: [BirthControl] = [.combinedPill, .miniPill, .ring, .patch, .implant]

    /// "Medicines and your pill", "Medicines and your ring"…
    static func medicinesTitle(_ method: BirthControl) -> String {
        "Medicines and your \(method == .combinedPill || method == .miniPill ? "pill" : method.inSentence)"
    }

    static func medicineLines(_ method: BirthControl) -> [String] {
        var out = ["Can make it work less well: rifampin or rifabutin (for TB), some seizure medicines (carbamazepine, oxcarbazepine, phenytoin, phenobarbital, primidone, topiramate at 200 mg a day or more), St John\u{2019}s wort, efavirenz (HIV), griseofulvin (fungal infections) and modafinil or armodafinil. Use condoms too while you take them and for 4 weeks after, and ask about a method they don\u{2019}t affect."]
        if method == .combinedPill || method == .miniPill {
            out.append("Tirzepatide (Mounjaro, Zepbound): use condoms for 4 weeks after starting and after each dose increase.")
        }
        out.append("Most antibiotics don\u{2019}t affect it. Rifampin is the exception.")
        if method.hasBreakWeek {
            out.append("It can lower lamotrigine levels, so tell whoever prescribes lamotrigine.")
        }
        out.append("Tell any doctor or pharmacist that you use it.")
        return out
    }
}

/// "Missed or late?" rules for her method, folded away until she opens it.
/// Shows nothing for methods with nothing to miss day to day (IUDs,
/// implant, shot). The same rules are a Health guide article.
struct MissedDoseCard: View {
    let method: BirthControl
    @Environment(\.colorScheme) private var scheme
    @State private var open = false

    var body: some View {
        if CycleCare.missedDoseMethods.contains(method) {
            Card(accent: .yellow) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Accent.yellow.ink(scheme))
                            .accessibilityHidden(true)
                        Text(CycleCare.missedDoseTitle(method)).font(.bodyEmphasis)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.secondary).fontWeight(.bold)
                            .foregroundStyle(Palette(scheme: scheme).tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(open ? "Hides what to do" : "Shows what to do")
                if open {
                    ForEach(CycleCare.missedDoseRules(method), id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Accent.yellow.fill(scheme)).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
                            Text(line).font(.bodyText).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(CycleCare.missedDoseSource)
                        .font(.secondary).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Medicines

/// Medicines that can make her method work less well (Shah F4): a short
/// list for the Learn screen. Nothing for IUDs or the shot.
struct BirthControlMedicinesCard: View {
    let method: BirthControl
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if CycleCare.medicineMethods.contains(method) {
            Card {
                SectionLabel(text: CycleCare.medicinesTitle(method))
                ForEach(CycleCare.medicineLines(method), id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Accent.indigo.fill(scheme)).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
                        Text(line).font(.bodyText).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Safety rows

/// Her method's safety reading, each row opening its Health guide article.
/// "Missed or late?" stays in view (the one she needs at 11pm); the rest
/// (being sick, medicines, eating enough for training, what isn't shown,
/// when to get bleeding checked) fold into one "Pill safety and info" row
/// that lists them (F22). Only the rows that apply to her method.
struct MethodSafetyRows: View {
    let method: BirthControl

    /// One row and the article it opens.
    fileprivate struct Row: Identifiable {
        var id: String { article.id }
        var article: GuideArticle
        var systemImage: String
        var accent: Accent
        /// A word or two for the folded row's note ("being sick").
        var short: String
    }

    private var missed: Row? {
        GuideArticle.missedDose(for: method).map { Row(article: $0, systemImage: "exclamationmark.circle.fill", accent: .yellow, short: "") }
    }

    private var rows: [Row] {
        [
            GuideArticle.sickOnMethod(for: method).map { Row(article: $0, systemImage: "cross.case.fill", accent: .pink, short: "being sick") },
            GuideArticle.medicines(for: method).map { Row(article: $0, systemImage: "pills.fill", accent: .indigo, short: "medicines") },
            GuideArticle.eatingEnough(for: method).map { Row(article: $0, systemImage: "fork.knife", accent: .mint, short: "eating enough") },
            GuideArticle.notShown(for: method).map { Row(article: $0, systemImage: "nosign", accent: .purple, short: "what isn\u{2019}t shown") },
            GuideArticle.bleedingCheck(for: method).map { Row(article: $0, systemImage: "drop.fill", accent: .coral, short: "bleeding checks") },
        ].compactMap { $0 }
    }

    /// "Being sick, medicines and more".
    private func foldedNote(_ rest: [Row]) -> String {
        let named = rest.prefix(2).map(\.short).joined(separator: ", ")
        let text = rest.count > 2 ? named + " and more" : rest.map(\.short).joined(separator: " and ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Pill safety and info", "Ring safety and info"…
    private var heading: String {
        switch method {
        case .combinedPill, .miniPill: "Pill safety and info"
        case .ring: "Ring safety and info"
        case .patch: "Patch safety and info"
        default: "Birth control safety and info"
        }
    }

    var body: some View {
        let rest = rows
        if missed != nil || !rest.isEmpty {
            RowCard {
                if let missed {
                    if method == .combinedPill {
                        // Two taps to one answer (H-A2); the rules are one tap further.
                        MetricRow(title: missed.article.title, note: "Two taps to what to do now",
                                  systemImage: missed.systemImage, accent: missed.accent) {
                            MissedPillHelper()
                        }
                    } else {
                        articleRow(missed)
                    }
                    if !rest.isEmpty { RowDivider() }
                }
                if rest.count == 1, let only = rest.first {
                    articleRow(only)
                } else if !rest.isEmpty {
                    MetricRow(title: heading, note: foldedNote(rest),
                              systemImage: "checkmark.shield.fill", accent: .indigo) {
                        MethodSafetyPage(title: heading, rows: rest)
                    }
                }
            }
        }
    }

    private func articleRow(_ row: Row) -> some View {
        MetricRow(title: row.article.title, note: row.article.summary,
                  systemImage: row.systemImage, accent: row.accent) {
            GuideArticleView(article: row.article)
        }
    }
}

/// The folded safety rows, one per article.
private struct MethodSafetyPage: View {
    let title: String
    let rows: [MethodSafetyRows.Row]

    var body: some View {
        Screen(title: title, accent: .indigo) {
            RowCard {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { RowDivider() }
                    MetricRow(title: row.article.title, note: row.article.summary,
                              systemImage: row.systemImage, accent: row.accent) {
                        GuideArticleView(article: row.article)
                    }
                }
            }
        }
    }
}

/// "No period for 3 months": one line at the top of Cycle while it's true,
/// the full note in a sheet (Okafor E, Ruiz F1). Natural cycles only.
struct NoPeriodCallout: View {
    @EnvironmentObject var model: AppModel
    @State private var showing = false

    var body: some View {
        if model.showsNoPeriodPrompt {
            CalloutBar(text: "No period for 3 months: worth seeing a clinician.", systemImage: "drop.fill") {
                showing = true
            }
            .bottomSheet(isPresented: $showing, title: "No period for 3 months") {
                Text(CycleCare.noPeriodThreeMonths)
                    .font(.bodyText).fixedSize(horizontal: false, vertical: true)
                Text(CycleCare.redS)
                    .font(.bodyText).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Cycle patterns

/// "Worth mentioning to a clinician": short or long cycles, a wide spread,
/// or few periods a year (Okafor L), and a note after stopping hormonal
/// birth control. Natural cycles only (no method, or the copper IUD). Three
/// months without a period is `NoPeriodCallout`, at the top of Cycle.
struct CycleCareNotes: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let note = model.cyclePatternNote {
            Card(accent: .indigo) {
                Text(note.title).font(.bodyEmphasis)
                    .accessibilityAddTraits(.isHeader)
                Text(note.text)
                    .font(.bodyText).fixedSize(horizontal: false, vertical: true)
            }
        }
        if model.recentlyChangedMethod {
            Card {
                Text("Stopped hormonal birth control recently? Cycles can take a few months to settle, and you can get pregnant right away. The app counts your usual length only from cycles since your last change.")
                    .font(.bodyText).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
