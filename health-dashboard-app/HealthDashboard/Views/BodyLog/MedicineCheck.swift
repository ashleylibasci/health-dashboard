import SwiftUI
import HealthCore

/// "Taking something new?" (H-A9): she types a medicine and gets one line
/// for her method, from the list in `CycleCare.medicineLines` (CDC US MEC
/// and SPR 2024) plus common ones that don't affect it. Sits at the top of
/// the "Medicines and your pill" guide article.
enum MedicineCheck {
    enum Effect {
        /// Makes the method work less well (enzyme inducers).
        case lowers
        /// Topiramate: only at 200 mg a day or more.
        case topiramate
        /// Tirzepatide slows the stomach: pills only.
        case tirzepatide
        /// Estrogen lowers lamotrigine levels.
        case lamotrigine
        /// Ella (ulipristal) and hormones work against each other.
        case ella
        case none
    }

    struct Entry {
        /// What she might type: the generic name first, then brand names.
        var names: [String]
        var effect: Effect
        var name: String { names[0] }
    }

    static let entries: [Entry] = [
        Entry(names: ["rifampin", "rifampicin", "rifadin"], effect: .lowers),
        Entry(names: ["rifabutin", "mycobutin"], effect: .lowers),
        Entry(names: ["carbamazepine", "tegretol"], effect: .lowers),
        Entry(names: ["oxcarbazepine", "trileptal"], effect: .lowers),
        Entry(names: ["phenytoin", "dilantin"], effect: .lowers),
        Entry(names: ["phenobarbital"], effect: .lowers),
        Entry(names: ["primidone", "mysoline"], effect: .lowers),
        Entry(names: ["topiramate", "topamax"], effect: .topiramate),
        Entry(names: ["St John\u{2019}s wort", "st johns wort", "st. john's wort", "st john's wort"], effect: .lowers),
        Entry(names: ["efavirenz", "sustiva", "atripla"], effect: .lowers),
        Entry(names: ["griseofulvin"], effect: .lowers),
        Entry(names: ["modafinil", "provigil"], effect: .lowers),
        Entry(names: ["armodafinil", "nuvigil"], effect: .lowers),
        Entry(names: ["tirzepatide", "mounjaro", "zepbound"], effect: .tirzepatide),
        Entry(names: ["lamotrigine", "lamictal"], effect: .lamotrigine),
        Entry(names: ["ella", "ulipristal"], effect: .ella),
        // Antibiotics (all but the rifamycins), antifungals other than
        // griseofulvin and SSRIs: no effect (CDC US MEC category 1).
        Entry(names: ["amoxicillin", "amoxil"], effect: .none),
        Entry(names: ["Augmentin", "amoxicillin-clavulanate"], effect: .none),
        Entry(names: ["azithromycin", "z-pak", "zithromax"], effect: .none),
        Entry(names: ["doxycycline"], effect: .none),
        Entry(names: ["minocycline"], effect: .none),
        Entry(names: ["cephalexin", "keflex"], effect: .none),
        Entry(names: ["ciprofloxacin", "cipro"], effect: .none),
        Entry(names: ["nitrofurantoin", "macrobid"], effect: .none),
        Entry(names: ["metronidazole", "flagyl"], effect: .none),
        Entry(names: ["clindamycin"], effect: .none),
        Entry(names: ["penicillin"], effect: .none),
        Entry(names: ["Bactrim", "sulfamethoxazole", "trimethoprim"], effect: .none),
        Entry(names: ["clarithromycin"], effect: .none),
        Entry(names: ["erythromycin"], effect: .none),
        Entry(names: ["fluconazole", "diflucan"], effect: .none),
        Entry(names: ["sertraline", "zoloft"], effect: .none),
        Entry(names: ["fluoxetine", "prozac"], effect: .none),
        Entry(names: ["escitalopram", "lexapro"], effect: .none),
        Entry(names: ["citalopram", "celexa"], effect: .none),
        Entry(names: ["ibuprofen", "advil", "motrin"], effect: .none),
        Entry(names: ["acetaminophen", "tylenol", "paracetamol"], effect: .none),
        Entry(names: ["naproxen", "aleve"], effect: .none),
    ]

    /// Up to three medicines whose names start with what she typed (3
    /// letters or more), each once.
    static func matches(_ query: String) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 3 else { return [] }
        return Array(entries.filter { e in e.names.contains { $0.lowercased().hasPrefix(q) } }.prefix(3))
    }

    /// The one line for her method.
    static func answer(_ entry: Entry, method: BirthControl) -> String {
        let thing = method == .combinedPill || method == .miniPill ? "pill" : method.inSentence
        switch entry.effect {
        case .lowers:
            return "Can make your \(thing) work less well. Use condoms too while you take it and for 4 weeks after."
        case .topiramate:
            return "At 200 mg a day or more it can make your \(thing) work less well: use condoms too while you take it and for 4 weeks after. Lower doses don\u{2019}t."
        case .tirzepatide:
            return method == .combinedPill || method == .miniPill
                ? "Use condoms for 4 weeks after starting it and after each dose increase."
                : "Doesn\u{2019}t affect your \(thing)."
        case .lamotrigine:
            return method.hasBreakWeek
                ? "Doesn\u{2019}t affect your \(thing), but your \(thing) can lower lamotrigine levels. Tell whoever prescribes it."
                : "Doesn\u{2019}t affect your \(thing)."
        case .ella:
            return method == .implant
                ? "Ask a pharmacist how ella fits with your implant."
                : "Ella and your \(thing) can each make the other work less well: wait 5 days after ella before your next \(thing), then use condoms for 7 days."
        case .none:
            return "Doesn\u{2019}t affect your \(thing)."
        }
    }

    static let notListed = "Not on the app\u{2019}s list. A pharmacist can tell you in a minute, no appointment needed."
}

/// The search box and its one-line answers.
struct MedicineCheckField: View {
    let method: BirthControl
    @State private var query = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        let found = MedicineCheck.matches(query)
        Card(accent: .indigo) {
            Text("Taking something new?").font(.cardTitle)
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(p.tertiary).accessibilityHidden(true)
                TextField("Type a medicine, like amoxicillin", text: $query)
                    .font(.bodyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: Sizes.minTap)
            .background(p.chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            if query.trimmingCharacters(in: .whitespaces).count >= 3 {
                if found.isEmpty {
                    Text(MedicineCheck.notListed)
                        .font(.bodyText).foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(found, id: \.name) { entry in
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(entry.name.prefix(1).uppercased() + entry.name.dropFirst()).font(.bodyEmphasis)
                            Text(MedicineCheck.answer(entry, method: method))
                                .font(.bodyText)
                                .foregroundStyle(entry.effect == .none ? Accent.mint.ink(scheme) : p.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
