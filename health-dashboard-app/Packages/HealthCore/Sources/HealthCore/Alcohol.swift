import Foundation

/// How big a pour was, in US standard drinks (14 g of alcohol: a 5 oz glass
/// of 12% wine, a 12 oz 5% beer or seltzer, a 1.5 oz shot of 40% spirits;
/// NIAAA). Party pours run 2 to 3 standard drinks, so "1 wine" from a red
/// cup undercounts. Each pour is rounded to the half drink, up where pours
/// vary, so a big night isn't undercounted.
public struct AlcoholPour: Hashable, Sendable, Identifiable {
    /// What the picture shows.
    public enum Picture: String, Hashable, Sendable { case glass, bigGlass, can, tallCan, redCup, cocktail, shot, doubleShot }

    /// "Wine.redCup".
    public var id: String
    /// "Wine", "Beer", "Seltzer", "Cocktail" or "Shot".
    public var kind: String
    /// On the button: "Red cup".
    public var label: String
    /// In a sentence: "red cup of wine" / "red cups of wine".
    public var one: String
    public var many: String
    /// About how much a "12 oz" or "16 oz" this is.
    public var size: String
    public var standardDrinks: Double
    public var picture: Picture

    /// The kind's usual serving: one standard drink.
    public var isStandard: Bool { id.hasSuffix(".standard") }

    /// "1 red cup of wine", "2 beers".
    public func phrase(count: Int) -> String { "\(count) \(count == 1 ? one : many)" }

    static func make(_ kind: String, _ key: String, _ label: String, _ one: String, _ many: String,
                     _ size: String, _ drinks: Double, _ picture: Picture) -> AlcoholPour {
        AlcoholPour(id: "\(kind).\(key)", kind: kind, label: label, one: one, many: many, size: size,
                    standardDrinks: drinks, picture: picture)
    }

    /// Every pour, the kind's usual serving first.
    public static let all: [AlcoholPour] = [
        make("Wine", "standard", "Glass", "glass of wine", "glasses of wine", "5 oz", 1, .glass),
        make("Wine", "big", "Big glass", "big glass of wine", "big glasses of wine", "9 oz", 2, .bigGlass),
        make("Wine", "redCup", "Red cup", "red cup of wine", "red cups of wine", "16 oz", 3, .redCup),
        make("Beer", "standard", "Can or bottle", "beer", "beers", "12 oz", 1, .can),
        make("Beer", "tall", "Tall can", "tall can of beer", "tall cans of beer", "16 oz", 1.5, .tallCan),
        make("Beer", "redCup", "Red cup", "red cup of beer", "red cups of beer", "16 oz", 1.5, .redCup),
        make("Seltzer", "standard", "Can", "seltzer", "seltzers", "12 oz, 5%", 1, .can),
        make("Seltzer", "tall", "Tall or strong", "tall or strong seltzer", "tall or strong seltzers", "16–19 oz, or 8%", 2, .tallCan),
        make("Cocktail", "standard", "Mixed drink", "cocktail", "cocktails", "1 shot", 1, .cocktail),
        make("Cocktail", "strong", "Strong cocktail", "strong cocktail", "strong cocktails", "margarita, Long Island", 2, .cocktail),
        make("Cocktail", "redCup", "Red cup", "red cup of punch", "red cups of punch", "16 oz mixed", 3, .redCup),
        make("Shot", "standard", "Shot", "shot", "shots", "1.5 oz", 1, .shot),
        make("Shot", "double", "Double", "double shot", "double shots", "3 oz", 2, .doubleShot),
    ]

    public static func pours(for kind: String) -> [AlcoholPour] { all.filter { $0.kind == kind } }

    public static func pour(id: String?) -> AlcoholPour? { id.flatMap { id in all.first { $0.id == id } } }

    /// A kind's usual serving (one standard drink).
    public static func standard(for kind: String) -> AlcoholPour? { pour(id: "\(kind).standard") }

    /// "3", "1.5": standard drinks in a sentence.
    public static func format(_ drinks: Double) -> String {
        drinks == drinks.rounded() ? "\(Int(drinks))" : String(format: "%.1f", drinks)
    }
}

/// When last night's alcohol has likely left her body. A standard drink
/// takes most women about 2 hours to clear (the app's alcohol tips), at a
/// steady pace that nothing speeds up: not coffee, water or sleep.
public enum AlcoholClearance {
    public static let hoursPerDrink = 2.0
    /// The morning after this many standard drinks gets the "not cleared
    /// until" card: 4 or more in an evening is binge drinking for women
    /// (NIAAA), the same line as the evening's safety note.
    public static let morningAfterDrinks = 4.0

    /// When the last of `drinks` (time, standard drinks) is cleared: each
    /// drink adds to what's in the body, which drops by one drink every
    /// `hoursPerDrink` while any is left. Rounded up to the half hour, so
    /// "about 11am" is never early. Nil without drinks.
    public static func clearTime(_ drinks: [(date: Date, standardDrinks: Double)], hoursPerDrink: Double = hoursPerDrink,
                                 calendar: Calendar = .current) -> Date? {
        let sorted = drinks.filter { $0.standardDrinks > 0 }.sorted { $0.date < $1.date }
        guard var t = sorted.first?.date else { return nil }
        let perSecond = 1 / (hoursPerDrink * 3600)
        var level = 0.0
        for d in sorted {
            level = max(0, level - d.date.timeIntervalSince(t) * perSecond) + d.standardDrinks
            t = d.date
        }
        let clear = t.addingTimeInterval(level / perSecond)
        let minute = calendar.component(.minute, from: clear), second = calendar.component(.second, from: clear)
        let past = (minute % 30) * 60 + second
        return past == 0 ? clear : clear.addingTimeInterval(Double(30 * 60 - past))
    }
}
