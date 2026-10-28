import XCTest
@testable import HealthCore

/// Brainstorm build (Oct 28): caffeine, alcohol, water and baselines.
final class FuelTests: XCTestCase {

    // D4: sizes scale the caffeine, to the 5 mg; regular is as listed.
    func testDrinkSizes() {
        XCTAssertEqual(DrinkSize.regular.mg(137), 137)
        XCTAssertEqual(DrinkSize.small.mg(140), 95)
        XCTAssertEqual(DrinkSize.large.mg(235), 315)
        XCTAssertEqual(DrinkSize.extraLarge.mg(150), 300)   // a venti cold brew is about 2× a tall
        XCTAssertEqual(DrinkSize.allCases.map(\.shopName), ["short", "tall", "grande", "venti"])
    }

    // E4: over-limit nights against the rest, only with 20 nights and 5 a side.
    func testCaffeineSleepComparison() {
        typealias N = CaffeineSleepComparison.Night
        let over = Array(repeating: N(caffeineAtBedtime: 60, minutesToFallAsleep: 30), count: 6)
        let under = Array(repeating: N(caffeineAtBedtime: 10, minutesToFallAsleep: 16), count: 14)
        let c = CaffeineSleepComparison.make(over + under)
        XCTAssertTrue(c.enoughData)
        XCTAssertEqual(c.minutesLonger, 14)
        XCTAssertEqual(c.over, 6)
        XCTAssertFalse(CaffeineSleepComparison.make(Array((over + under).prefix(19))).enoughData)
        XCTAssertFalse(CaffeineSleepComparison.make(under + under).enoughData)   // nothing over the limit
        XCTAssertNil(CaffeineSleepComparison.make(under).minutesLonger)
        // Exactly the limit counts as under.
        XCTAssertEqual(CaffeineSleepComparison.make([N(caffeineAtBedtime: 35, minutesToFallAsleep: 5)]).under, 1)
    }

    // D2: every kind has its usual serving (1 standard drink) first, and a
    // red cup of wine is about 3.
    func testPours() {
        for kind in ["Wine", "Beer", "Seltzer", "Cocktail", "Shot"] {
            let pours = AlcoholPour.pours(for: kind)
            XCTAssertGreaterThanOrEqual(pours.count, 2, kind)
            XCTAssertEqual(pours.first?.standardDrinks, 1, kind)
            XCTAssertEqual(pours.first?.isStandard, true, kind)
            XCTAssertEqual(AlcoholPour.standard(for: kind), pours.first)
        }
        XCTAssertEqual(AlcoholPour.pour(id: "Wine.redCup")?.standardDrinks, 3)
        XCTAssertEqual(AlcoholPour.pour(id: "Wine.redCup")?.phrase(count: 2), "2 red cups of wine")
        XCTAssertEqual(AlcoholPour.standard(for: "Beer")?.phrase(count: 1), "1 beer")
        XCTAssertNil(AlcoholPour.pour(id: nil))
        XCTAssertEqual(AlcoholPour.format(1.5), "1.5")
        XCTAssertEqual(AlcoholPour.format(3), "3")
    }

    // D1: 2 hours a standard drink, from the first drink, never early.
    func testAlcoholClearance() {
        let cal = Calendar(identifier: .gregorian)
        let ten = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 22))!
        func at(_ h: Double) -> Date { ten.addingTimeInterval(h * 3600) }
        XCTAssertNil(AlcoholClearance.clearTime([], calendar: cal))
        // A red cup of wine (3) at 10pm and 2 shots at 11:30pm: 1.5 h of
        // clearing leaves 2.25, plus 2 is 4.25 drinks = 8.5 h → 8am.
        XCTAssertEqual(AlcoholClearance.clearTime([(ten, 3), (at(1.5), 2)], calendar: cal), at(10))
        // Drinks far apart don't stack: 1 at 10pm is gone by midnight.
        XCTAssertEqual(AlcoholClearance.clearTime([(ten, 1), (at(4), 1)], calendar: cal), at(6))
        // Rounded up to the half hour.
        XCTAssertEqual(AlcoholClearance.clearTime([(at(0.25), 1)], calendar: cal), at(2.5))
    }
}
