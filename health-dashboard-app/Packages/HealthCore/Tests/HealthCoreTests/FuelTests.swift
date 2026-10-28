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
}
