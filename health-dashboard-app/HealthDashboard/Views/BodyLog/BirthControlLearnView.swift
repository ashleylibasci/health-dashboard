import SwiftUI
import HealthCore

/// What her birth control does in her body and to her Watch data, what the
/// app turns off and why, and every method compared.
struct BirthControlLearnView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Screen(title: "Learn", accent: .indigo) {
            if let bc = store.birthControl {
                yourMethod(bc)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Birth control and")
                    Text("your Watch data").foregroundStyle(Accent.indigo.ink(scheme))
                }
                .font(.scaled(size: 30, weight: .bold))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Text("You haven't added a birth control method. If you use one (hormonal or a copper IUD), add it in Settings and the app adjusts what it shows.")
                    .font(.scaled(size: 16)).secondaryText().fixedSize(horizontal: false, vertical: true)
                Card {
                    LinkRow(title: "Cycle & birth control settings", systemImage: "slider.horizontal.3", accent: .purple) { SettingsView() }
                }
            }
            comparison
            Card(accent: .coral) {
                Text("Never change your birth control because of this app").font(.scaled(size: 15, weight: .bold))
                Text("Talk to your doctor or nurse before starting, stopping or switching. This app is not birth control.")
                    .font(.scaled(size: 14)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            if let url = URL(string: "https://www.nhs.uk/contraception/") {
                Link(destination: url) {
                    Label("Learn more from the NHS", systemImage: "arrow.up.right.square")
                        .font(.scaled(size: 15, weight: .semibold))
                        .foregroundStyle(Accent.indigo.ink(scheme))
                        .frame(minHeight: 44)
                }
            }
        }
    }

    // MARK: Your method

    private func ovulationLine(_ bc: BirthControl) -> String {
        switch bc.ovulation {
        case .stopped: return "Stops ovulation. You don't release an egg each month, so you don't have the natural phases (follicular, ovulation, luteal)."
        case .sometimes: return "Ovulation stops for some people and not for others, so you may or may not release an egg each cycle."
        case .mostStill: return "Most people still ovulate, so the natural phases still apply to you."
        case .natural: return "No hormones, so you ovulate normally and have a natural cycle."
        }
    }

    @ViewBuilder
    private func yourMethod(_ bc: BirthControl) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How the")
            Text(bc.rawValue.lowercased()).foregroundStyle(Accent.indigo.ink(scheme))
            Text("works in your body")
        }
        .font(.scaled(size: 30, weight: .bold))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)

        Card {
            SectionLabel(text: "Your cycle")
            Text(ovulationLine(bc)).font(.scaled(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(bc.note).font(.scaled(size: 14)).secondaryText().fixedSize(horizontal: false, vertical: true)
            if bc.hasBreakWeek { packBar(bc) }
        }

        watchDataCard(bc)

        if bc.ovulation == .stopped {
            Card {
                SectionLabel(text: "What the app turns off, and why")
                Text("Egg-release estimates, fertile days and phase-based predictions. Your method changes your natural temperature pattern, so those wouldn't mean anything. Apple's Health app does the same.")
                    .font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
            }
        }

        noticeCard(bc)

        if bc == .combinedPill || bc == .ring || bc == .patch {
            Card(accent: .pink) {
                Text("Get care right away if").font(.scaled(size: 15, weight: .bold)).foregroundStyle(Accent.pink.ink(scheme))
                Text("Leg pain or swelling, chest pain, or sudden shortness of breath. These can be signs of a blood clot, a rare risk with estrogen. New migraines with aura: tell your doctor.")
                    .font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hasBreak: Bool { store.data.packActiveDays < store.data.packLength }
    private var activeShare: CGFloat {
        CGFloat(store.data.packActiveDays) / CGFloat(max(store.data.packLength, 1))
    }

    private func packBar(_ bc: BirthControl) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 6).fill(BodyLogStyle.packFill(isBreak: false, scheme))
                        .frame(width: max(0, (geo.size.width - 4) * activeShare))
                    if hasBreak {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(BodyLogStyle.packFill(isBreak: true, scheme), lineWidth: 2)
                    }
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)
            HStack {
                Text("Active \(bc == .combinedPill ? "pills" : bc == .ring ? "ring" : "patches") \u{00B7} \(store.data.packActiveDays) days")
                Spacer()
                Text(hasBreak ? "Break \u{00B7} \(store.data.packLength - store.data.packActiveDays) days" : "No break")
            }
            .font(.scaled(size: 12, weight: .semibold))
            .secondaryText()
            HStack(alignment: .top, spacing: 0) {
                Text("The bleed in your break week is a withdrawal bleed, caused by the hormones pausing. It isn't a true period. Skipping the break on purpose is fine for most combined pills, rings and patches (you can mark it in your pack settings); if your pack has pills in more than one color, ask a pharmacist how.")
                    .font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
                InfoButton(topic: .withdrawalBleed).padding(.vertical, -10)
            }
        }
    }

    private func watchDataCard(_ bc: BirthControl) -> some View {
        Card(accent: .indigo) {
            SectionLabel(text: "What changes in your Watch data", accent: .indigo)
            switch bc.ovulation {
            case .stopped:
                bullet("Temperature tends to sit a little higher and stay flat, instead of rising mid-month.")
                bullet("Heart rate and HRV swing less across the month than in a natural cycle, so a change is more likely about sleep, stress or getting sick.")
                if bc.hasBreakWeek {
                    bullet("Sleep: small lab studies saw a little less deep sleep on active pills. Too early to say it matters.")
                }
            case .sometimes:
                bullet("In cycles where you ovulate, temperature rises afterward and HRV dips a little; in cycles where you don't, they stay flat.")
                bullet("The app shows phases as a rough guide and skips the period countdown.")
            case .mostStill:
                bullet("Temperature, HRV and resting heart rate usually follow your natural phases.")
                bullet("Bleeding is often lighter or stops, so the app shows phases from your last logged period but no period countdown.")
            case .natural:
                bullet("Your data follows a natural cycle: temperature and resting heart rate rise after ovulation, HRV dips a little.")
            }
        }
    }

    private struct Notice: Hashable {
        let text: String
        let evidence: String
        let accent: Accent
    }

    private func notices(_ bc: BirthControl) -> [Notice] {
        switch bc {
        case .combinedPill, .ring, .patch:
            return [Notice(text: "Clearer skin", evidence: "Strong evidence", accent: .mint),
                    Notice(text: "Mood changes", evidence: "Mixed evidence", accent: .yellow),
                    Notice(text: "Spotting in the first months", evidence: "Common", accent: .blue),
                    Notice(text: "Weight gain", evidence: "Not supported", accent: .indigo)]
        case .miniPill, .implant:
            return [Notice(text: "Unpredictable bleeding or spotting", evidence: "Very common", accent: .blue),
                    Notice(text: "Mood changes", evidence: "Mixed evidence", accent: .yellow),
                    Notice(text: "Acne", evidence: "Sometimes", accent: .coral)]
        case .shot:
            return [Notice(text: "Periods stop after a few shots", evidence: "Very common", accent: .blue),
                    Notice(text: "Some weight gain", evidence: "Some evidence", accent: .yellow),
                    Notice(text: "Fertility takes months to return after stopping", evidence: "Common", accent: .indigo)]
        case .hormonalIUD:
            return [Notice(text: "Lighter periods, or none", evidence: "Very common", accent: .mint),
                    Notice(text: "Spotting in the first months", evidence: "Common", accent: .blue),
                    Notice(text: "Acne", evidence: "Sometimes", accent: .coral)]
        case .copperIUD:
            return [Notice(text: "Heavier or longer periods", evidence: "Common", accent: .coral),
                    Notice(text: "More cramping, often easing after months", evidence: "Common", accent: .yellow)]
        }
    }

    private func noticeCard(_ bc: BirthControl) -> some View {
        Card {
            SectionLabel(text: "Other things people notice")
            ForEach(notices(bc), id: \.self) { n in
                HStack {
                    Text(n.text).font(.scaled(size: 15))
                    Spacer()
                    Text(n.evidence)
                        .font(.scaled(size: 12, weight: .bold))
                        .foregroundStyle(n.accent.ink(scheme))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(n.accent.tint(scheme), in: Capsule())
                }
                .frame(minHeight: 32)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Accent.indigo.fill(scheme)).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
            Text(text).font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: All methods

    private func tag(_ o: BirthControl.Ovulation) -> (String, Accent) {
        switch o {
        case .stopped: ("Stops ovulation", .indigo)
        case .sometimes: ("Sometimes ovulate", .yellow)
        case .mostStill: ("Most still ovulate", .orange)
        case .natural: ("Natural cycle", .mint)
        }
    }

    private func appShows(_ bc: BirthControl) -> String {
        if bc.hasBreakWeek { return "App shows: pack day, active and break weeks" }
        switch bc.ovulation {
        case .stopped: return "App shows: no phases, no countdown"
        case .sometimes: return "App shows: phases as a rough guide, no countdown"
        case .mostStill, .natural: return "App shows: your phases"
        }
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "All methods compared").padding(.top, 6)
            Card(padding: 12) {
                ForEach(Array(BirthControl.allCases.enumerated()), id: \.element) { index, bc in
                    if index > 0 { Divider().overlay(Palette(scheme: scheme).cardBorder) }
                    methodRow(bc)
                }
            }
        }
    }

    private func methodRow(_ bc: BirthControl) -> some View {
        let (label, accent) = tag(bc.ovulation)
        let mine = store.birthControl == bc
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(bc.rawValue).font(.scaled(size: 15, weight: .bold))
                if mine {
                    Text("Yours").font(.scaled(size: 11, weight: .bold)).foregroundStyle(Accent.indigo.ink(scheme))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Accent.indigo.tint(scheme), in: Capsule())
                }
                Spacer()
                Text(label).font(.scaled(size: 11, weight: .bold)).foregroundStyle(accent.ink(scheme))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accent.tint(scheme), in: Capsule())
            }
            Text(bc.note).font(.scaled(size: 13)).secondaryText().fixedSize(horizontal: false, vertical: true)
            Text(appShows(bc)).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(accent.ink(scheme))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
