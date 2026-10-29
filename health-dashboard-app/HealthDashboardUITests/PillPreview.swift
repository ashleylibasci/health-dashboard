import XCTest

/// Preview screenshots of the phase 2 pill features (missed-pill helper,
/// pill callouts, medicines, bleeds and mood by pack, break-week pattern,
/// pack-day baselines, the visit summary, export), on example data.
/// `TEST_RUNNER_SHOT_DIR=/folder xcodebuild test … -only-testing:HealthDashboardUITests/PillPreview`.
final class PillPreview: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ args: [String], appearance: String = "dark", textSize: String? = nil) {
        app = XCUIApplication()
        app.launchArguments += ["-demo", "-appearance", appearance, "-resetData", "-demoCycle", "pill", "-demoPillHistory"] + args
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
        sleep(3)
    }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] else { return }
        try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    /// The first hittable element whose label starts with `text`, scrolling to find it.
    @discardableResult
    private func tap(_ text: String, scrolls: Int = 6) -> Bool {
        let q = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text))
        for i in 0...(scrolls * 2 + 1) {
            if let el = q.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                el.tap()
                sleep(1)
                return true
            }
            if i < scrolls { app.swipeUp() } else { app.swipeDown() }
        }
        XCTFail("Couldn't find \(text)")
        return false
    }

    /// Scrolls until an element starting with `text` is on screen.
    private func scroll(to text: String) {
        let q = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text))
        for _ in 0..<8 where !(q.firstMatch.exists && q.firstMatch.isHittable) { app.swipeUp(velocity: .slow) }
        sleep(1)
    }

    private func back() {
        let b = app.navigationBars.buttons.firstMatch
        if b.exists { b.tap() } else { app.swipeRight() }
        sleep(1)
    }

    func test1CycleScreens() {
        launch(["-demoOpen", "cycle"])
        scroll(to: "Summary for your pill visit")
        shot("H-A4-H-A10-H-B1-H-G1-cycle-rows")
        tap("Your break weeks")
        shot("H-A4-break-week-sheet")
        tap("Done")
        tap("Mood by pack day")
        sleep(1)
        shot("H-B1-mood-by-pack-day")
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("H-B1-mood-by-pack-day-2")
        back()
        tap("Bleeds by pack")
        shot("H-A10-bleeds-by-pack")
        back()
        tap("Summary for your pill visit")
        sleep(2)
        shot("H-G1-screen")
        back()
        tap("Missed or late pill?")
        shot("H-A2-helper")
        tap("Two or more")
        tap("Pill 17")
        shot("H-A2-two-or-more")
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("H-A2-two-or-more-2")
        app.swipeDown(velocity: .slow)
        tap("One")
        shot("H-A2-one")
        back()
        tap("Pill safety and info")
        tap("Medicines and your pill")
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("rifampin")
        sleep(1)
        shot("H-A9-rifampin")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "amoxicillin")
        sleep(1)
        shot("H-A9-amoxicillin")
    }

    func test2LogMoodScales() {
        launch([])
        app.tabBars.buttons["Log"].tap()
        sleep(1)
        tap("Add mood")
        tap("Mood 4")
        tap("Anxiety 2")
        scroll(to: "Irritability 5")
        shot("H-B1-log-scales")
    }

    func test3SickCallout() {
        launch(["-demoPillEvent", "vomiting", "-demoOpen", "cycle"])
        shot("H-A7-callout")
        tap("Sick on the pill")
        shot("H-A7-sheet")
    }

    func test4SpottingCallout() {
        launch(["-demoPillEvent", "spotting", "-demoOpen", "cycle"])
        shot("H-A8-callout")
        tap("Spotting on active pills")
        shot("H-A8-sheet")
    }

    func test5BreakDayRecovery() {
        launch(["-demoPackDay", "24", "-demoOpen", "recovery"])
        tap("What moved today")
        scroll(to: "Allowed for")
        shot("H-E2-recovery-break-week")
    }

    func test6DataSettings() {
        launch([])
        app.tabBars.buttons["Body"].tap()
        sleep(1)
        app.buttons["Settings and profile"].firstMatch.tap()
        sleep(1)
        tap("Apple Health & data")
        scroll(to: "Export logs as a spreadsheet")
        shot("H-G3-H-G4-data-settings")
    }

    func test7LightAndLargestText() {
        launch(["-demoOpen", "cycle"], appearance: "light")
        scroll(to: "Summary for your pill visit")
        shot("H-A4-H-A10-H-B1-cycle-rows-light")
        launch(["-demoOpen", "cycle"], textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        tap("Missed or late pill?")
        tap("Two or more")
        tap("Pill 17")
        shot("H-A2-ax5")
    }
}
