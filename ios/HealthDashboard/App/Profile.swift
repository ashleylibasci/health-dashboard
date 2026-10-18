import Foundation

/// Who's using the app and how they want it set up. Filled in by the welcome flow and
/// kept on the phone (UserDefaults); editable later from Settings.
struct Profile: Codable, Equatable {
    var name: String
    var birthday: Date?
    var cycle: CycleMode = .notTracking
    var birthControl: BirthControl?
    var conditions: Set<Condition> = []
    var prefs = Preferences()
    /// First day of the current pill, ring or patch pack (for pack-day tracking).
    var packStart: Date?
    /// Days a daily pill was marked taken, as local dates.
    var pillsTaken: Set<String> = []
    /// The water bottle she usually drinks from, in mL.
    var bottleMl: Double = 710

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var initial: String { firstName.first.map { String($0).uppercased() } ?? "•" }

    /// Whole years old today, if the birthday is set.
    var age: Int? {
        birthday.map { Calendar.current.dateComponents([.year], from: $0, to: .now).year ?? 0 }
    }

    var tracksCycle: Bool { cycle != .notTracking }
}

extension Profile {
    init(name: String, birthday: Date? = nil, cycle: CycleMode = .notTracking, birthControl: BirthControl? = nil,
         conditions: Set<Condition> = [], prefs: Preferences = Preferences(), packStart: Date? = nil, bottleMl: Double = 710) {
        self.name = name; self.birthday = birthday; self.cycle = cycle; self.birthControl = birthControl
        self.conditions = conditions; self.prefs = prefs; self.packStart = packStart; self.bottleMl = bottleMl
    }

    /// Fields added in later versions fall back to defaults, so an older saved profile still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        birthday = try c.decodeIfPresent(Date.self, forKey: .birthday)
        cycle = try c.decodeIfPresent(CycleMode.self, forKey: .cycle) ?? .notTracking
        birthControl = try c.decodeIfPresent(BirthControl.self, forKey: .birthControl)
        conditions = try c.decodeIfPresent(Set<Condition>.self, forKey: .conditions) ?? []
        prefs = try c.decodeIfPresent(Preferences.self, forKey: .prefs) ?? Preferences()
        packStart = try c.decodeIfPresent(Date.self, forKey: .packStart)
        pillsTaken = try c.decodeIfPresent(Set<String>.self, forKey: .pillsTaken) ?? []
        bottleMl = try c.decodeIfPresent(Double.self, forKey: .bottleMl) ?? 710
    }
}

enum CycleMode: String, Codable, CaseIterable, Identifiable {
    case natural, hormonal, irregular, notTracking
    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: "Natural cycle"
        case .hormonal: "Hormonal birth control"
        case .irregular: "Irregular or not sure"
        case .notTracking: "Not tracking a cycle"
        }
    }

    var detail: String {
        switch self {
        case .natural: "No hormonal birth control. The app learns your phases from your temperature and logs."
        case .hormonal: "Pill, IUD, implant, shot, ring or patch. Next, pick which one."
        case .irregular: "PCOS, a cycle that changes a lot, or you just don’t know yet. No countdowns."
        case .notTracking: "Pregnant, postpartum, menopause, or you’d just rather not. Cycle cards stay hidden."
        }
    }
}

enum BirthControl: String, Codable, CaseIterable, Identifiable {
    case combinedPill, miniPill, hormonalIUD, copperIUD, implant, shot, ring, patch
    var id: String { rawValue }

    var name: String {
        switch self {
        case .combinedPill: "Combined pill"
        case .miniPill: "Mini pill"
        case .hormonalIUD: "Hormonal IUD"
        case .copperIUD: "Copper IUD"
        case .implant: "Implant"
        case .shot: "Shot"
        case .ring: "Ring"
        case .patch: "Patch"
        }
    }

    var note: String {
        switch self {
        case .combinedPill: "Estrogen + progestin. Bleed on placebo week."
        case .miniPill: "Progestin only. Bleeding can be unpredictable."
        case .hormonalIUD: "Mirena, Kyleena… Periods often lighter or stop."
        case .copperIUD: "No hormones. Periods can be heavier."
        case .implant: "Nexplanon. Bleeding varies a lot."
        case .shot: "Depo-Provera, every 12–13 weeks."
        case .ring: "NuvaRing, Annovera. Like the pill."
        case .patch: "Weekly patch. Like the pill."
        }
    }

    enum Ovulation { case stops, sometimes, mostStill, natural }

    var ovulation: Ovulation {
        switch self {
        case .combinedPill, .implant, .shot, .ring, .patch: .stops
        case .miniPill: .sometimes
        case .hormonalIUD: .mostStill
        case .copperIUD: .natural
        }
    }

    var ovulationLabel: String {
        switch ovulation {
        case .stops: "Stops ovulation"
        case .sometimes: "Sometimes"
        case .mostStill: "Most still ovulate"
        case .natural: "Natural cycle"
        }
    }

    /// Methods that keep a pill-style 28-day pack with a withdrawal bleed.
    var hasPlaceboWeek: Bool { [.combinedPill, .ring, .patch].contains(self) }
}

enum Condition: String, Codable, CaseIterable, Identifiable {
    case pcos, endometriosis, thyroid, pmdd, anemia
    var id: String { rawValue }

    var name: String {
        switch self {
        case .pcos: "PCOS"
        case .endometriosis: "Endometriosis"
        case .thyroid: "Thyroid condition"
        case .pmdd: "PMDD"
        case .anemia: "Iron-deficiency anemia"
        }
    }

    var detail: String {
        switch self {
        case .pcos: "Polycystic ovary syndrome: irregular or missed periods, often longer cycles."
        case .endometriosis: "Tissue like the uterine lining grows outside it; painful periods are common."
        case .thyroid: "An over- or under-active thyroid changes resting heart rate, energy and cycles."
        case .pmdd: "Premenstrual dysphoric disorder: strong mood changes in the week or two before a period."
        case .anemia: "Low iron: tiredness and a higher resting heart rate, often worse after heavy periods."
        }
    }
}

struct Preferences: Codable, Equatable {
    var showCalories = false
    var sickAlerts = true
    var drinksTracking = true
    var streaks = false
    var darkWatchAtNight = true
    /// Switch the phone to the dark night version from 8pm to 6am.
    var nightMode = true

    init(showCalories: Bool = false, sickAlerts: Bool = true, drinksTracking: Bool = true, streaks: Bool = false, darkWatchAtNight: Bool = true, nightMode: Bool = true) {
        self.showCalories = showCalories; self.sickAlerts = sickAlerts; self.drinksTracking = drinksTracking
        self.streaks = streaks; self.darkWatchAtNight = darkWatchAtNight; self.nightMode = nightMode
    }

    /// Settings added later fall back to their defaults, so older saved profiles still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showCalories = (try? c.decodeIfPresent(Bool.self, forKey: .showCalories)) ?? false
        sickAlerts = (try? c.decodeIfPresent(Bool.self, forKey: .sickAlerts)) ?? true
        drinksTracking = (try? c.decodeIfPresent(Bool.self, forKey: .drinksTracking)) ?? true
        streaks = (try? c.decodeIfPresent(Bool.self, forKey: .streaks)) ?? false
        darkWatchAtNight = (try? c.decodeIfPresent(Bool.self, forKey: .darkWatchAtNight)) ?? true
        nightMode = (try? c.decodeIfPresent(Bool.self, forKey: .nightMode)) ?? true
    }
}

enum ProfileStore {
    private static let key = "profile.v1"

    static func load() -> Profile? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    static func save(_ profile: Profile?) {
        if let profile, let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
