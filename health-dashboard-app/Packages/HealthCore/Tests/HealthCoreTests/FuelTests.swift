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
}
