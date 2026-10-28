import SwiftUI
import HealthCore

// When to get care, missed pills and medicines that affect birth control.
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

/// "Missed or late?" rules for her method, folded away until she opens it
/// (CDC US SPR 2024; Okafor A, D; Shah F4). Shows nothing for methods with
/// nothing to miss day to day (IUDs, implant, shot).
struct MissedDoseCard: View {
    let method: BirthControl
    @Environment(\.colorScheme) private var scheme
    @State private var open = false

    static func applies(to method: BirthControl) -> Bool {
        [.combinedPill, .miniPill, .ring, .patch].contains(method)
    }

    private var title: String {
        switch method {
        case .ring: "Ring out, or put in late?"
        case .patch: "Patch off, or put on late?"
        default: "Missed or late pill?"
        }
    }

    private var rules: [String] {
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

    var body: some View {
        if Self.applies(to: method) {
            Card(accent: .yellow) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Accent.yellow.ink(scheme))
                            .accessibilityHidden(true)
                        Text(title).font(.scaled(size: 15, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.scaled(size: 13, weight: .bold))
                            .foregroundStyle(Palette(scheme: scheme).tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(open ? "Hides what to do" : "Shows what to do")
                if open {
                    ForEach(rules, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Accent.yellow.fill(scheme)).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
                            Text(line).font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("From the CDC\u{2019}s 2024 guidance. Not sure? A pharmacist can tell you what to do, no appointment needed.")
                        .font(.scaled(size: 12)).secondaryText()
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

    static func applies(to method: BirthControl) -> Bool {
        [.combinedPill, .miniPill, .ring, .patch, .implant].contains(method)
    }

    private var hasEstrogen: Bool { method.hasBreakWeek }

    private var lines: [String] {
        var out = ["Can make it work less well: rifampin or rifabutin (for TB), some seizure medicines (carbamazepine, oxcarbazepine, phenytoin, phenobarbital, primidone, topiramate at 200 mg a day or more), St John\u{2019}s wort, efavirenz (HIV), griseofulvin (fungal infections) and modafinil or armodafinil. Use condoms too while you take them and for 4 weeks after, and ask about a method they don\u{2019}t affect."]
        if method == .combinedPill || method == .miniPill {
            out.append("Tirzepatide (Mounjaro, Zepbound): use condoms for 4 weeks after starting and after each dose increase.")
        }
        out.append("Most antibiotics don\u{2019}t affect it. Rifampin is the exception.")
        if hasEstrogen {
            out.append("It can lower lamotrigine levels, so tell whoever prescribes lamotrigine.")
        }
        out.append("Tell any doctor or pharmacist that you use it.")
        return out
    }

    var body: some View {
        if Self.applies(to: method) {
            Card {
                SectionLabel(text: "Medicines and your \(method == .combinedPill || method == .miniPill ? "pill" : method.inSentence)")
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Accent.indigo.fill(scheme)).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
                        Text(line).font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Cycle patterns

/// "Worth mentioning to a clinician": short or long cycles, a wide spread,
/// or few periods a year (Okafor L), and 3 months without a period (Okafor
/// E, Ruiz F1). Natural cycles only (no method, or the copper IUD).
struct CycleCareNotes: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if model.showsNoPeriodPrompt {
            Card(accent: .coral) {
                Text("No period for 3 months").font(.scaled(size: 15, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(CycleCare.noPeriodThreeMonths)
                    .font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
                Text(CycleCare.redS)
                    .font(.scaled(size: 14)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
        }
        if let note = model.cyclePatternNote {
            Card(accent: .indigo) {
                Text(note.title).font(.scaled(size: 15, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(note.text)
                    .font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
            }
        }
        if model.recentlyChangedMethod {
            Card {
                Text("Stopped hormonal birth control recently? Cycles can take a few months to settle, and you can get pregnant right away. The app counts your usual length only from cycles since your last change.")
                    .font(.scaled(size: 14)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
