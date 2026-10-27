import SwiftUI
import HealthCore

/// Living with PCOS: what it is, how it shows up in Watch data, what the app
/// does differently, and trusted links.
struct PCOSView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    private var added: Bool { store.data.conditions.contains("PCOS") }

    var body: some View {
        Screen(title: "PCOS", accent: .mint) {
            if added {
                Label("Added to your profile", systemImage: "checkmark.circle.fill")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.mint.ink(scheme))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Accent.mint.tint(scheme), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Living with")
                Text("PCOS").foregroundStyle(Accent.mint.ink(scheme))
            }
            .font(.scaled(size: 32, weight: .bold))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(whatItIs).font(.scaled(size: 16)).fixedSize(horizontal: false, vertical: true)

            listCard("How it can show up in your data", accent: .indigo, items: dataItems)
            listCard("What the app does differently", accent: .mint, items: appItems)

            Card {
                SectionLabel(text: "Extra things you can log")
                // Only things the log really has: symptoms and spotting.
                FlowChips(items: ["Acne", "Hair changes", "Spotting", "Fatigue", "Mood swings", "Cramps"])
                Text("How awake you feel goes in the morning check-in. The app doesn\u{2019}t log medications; note changes to them for your doctor.")
                    .font(.scaled(size: 13)).secondaryText().fixedSize(horizontal: false, vertical: true)
                LinkRow(title: "Log bleeding and symptoms", systemImage: "square.and.pencil", accent: .coral) {
                    CycleLogView()
                }
            }

            Card(accent: .coral) {
                Text("Talk to a doctor if").font(.scaled(size: 15, weight: .bold))
                Text("Your period stops for 3 months or more, bleeding is very heavy, or anything feels off. Many PCOS treatments change cycles, so update the app if yours changes.")
                    .font(.scaled(size: 14)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }

            Card {
                SectionLabel(text: "Trusted info")
                if let nichd = URL(string: "https://www.nichd.nih.gov/health/topics/pcos") {
                    Link(destination: nichd) {
                        Label("PCOS basics \u{00B7} NIH (NICHD)", systemImage: "arrow.up.right.square").frame(minHeight: 44)
                    }
                }
                if let community = URL(string: "https://pcoschallenge.org") {
                    Link(destination: community) {
                        Label("Support community \u{00B7} PCOS Challenge", systemImage: "arrow.up.right.square").frame(minHeight: 44)
                    }
                }
            }
            .font(.scaled(size: 14, weight: .semibold))
            .foregroundStyle(Accent.indigo.ink(scheme))

            Button {
                if added { store.data.conditions.removeAll { $0 == "PCOS" } } else { store.data.conditions.append("PCOS") }
            } label: {
                Text(added ? "Remove PCOS from my profile" : "Add PCOS to my profile")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle((added ? Accent.pink : Accent.mint).ink(scheme))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)

            Text("General information, not medical advice. The app can\u{2019}t diagnose PCOS or any condition.")
                .font(.scaled(size: 12)).secondaryText()
        }
    }

    private var whatItIs: String {
        model.ovulationStopped
            ? "Polycystic ovary syndrome is a common hormone condition. Without hormonal birth control, cycles can be far apart or unpredictable. Your current method sets your bleeding pattern, so the app follows your method."
            : "Polycystic ovary syndrome is a common hormone condition. Ovulation can happen late, irregularly, or not every cycle, so periods can be far apart or unpredictable."
    }

    private var dataItems: [String] {
        model.ovulationStopped
            ? ["Bleeding follows your birth control, not PCOS, while you're on it.",
               "Skin and hair changes are worth logging; some methods help with them."]
            : ["Long or uneven gaps between periods.",
               "Some cycles may have no ovulation at all. Watch and phone cycle estimates are mostly tested on regular cycles, so treat any estimate loosely."]
    }

    private var appItems: [String] {
        var items = ["No period countdowns and no \u{201C}late period\u{201D} wording.",
                     "Keeps a history of your cycle lengths, from the periods you log, that you can show your doctor.",
                     "Adds \u{201C}Hair changes\u{201D} to the symptom log."]
        if !model.ovulationStopped {
            items.insert("Counts days since your last period started instead of predicting the next one.", at: 1)
        }
        return items
    }

    private func listCard(_ title: String, accent: Accent, items: [String]) -> some View {
        Card {
            SectionLabel(text: title, accent: accent)
            ForEach(items, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(accent.fill(scheme)).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
                    Text(line).font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Small non-interactive tags in rows of three.
private struct FlowChips: View {
    let items: [String]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.scaled(size: 13, weight: .semibold))
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Palette(scheme: scheme).chip, in: Capsule())
            }
        }
    }
}
