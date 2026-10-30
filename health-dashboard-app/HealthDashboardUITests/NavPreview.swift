import XCTest

/// Preview screenshots of the navigation ideas (search, quick log, the
/// Health guide button, Body's summary, empty states, the end of setup,
/// the day-3 hello card), on example data.
/// `TEST_RUNNER_SHOT_DIR=/folder xcodebuild test … -only-testing:HealthDashboardUITests/NavPreview`.
final class NavPreview: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ args: [String] = [], appearance: String = "dark", textSize: String? = nil, cycle: Bool = true) {
        app = XCUIApplication()
        app.launchArguments += ["-appearance", appearance, "-resetData"] + (cycle ? ["-demoCycle", "pill"] : ["-demo"]) + args
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
        sleep(3)
        dismissSystemAlert()
    }

    /// The notification permission prompt, if iOS shows it.
    private func dismissSystemAlert() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap(); sleep(1) }
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

    private func back() {
        let b = app.navigationBars.buttons.firstMatch
        if b.exists { b.tap() } else { app.swipeRight() }
        sleep(1)
    }

    /// A short pull from the top of the page, the way she'd reveal search.
    private func pullDown() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
    }

    func test1Search() {
        launch()
        shot("D-S1-1-today-field-tucked")
        pullDown()
        shot("D-S1-2-pulled-down")
        app.buttons["Search"].firstMatch.tap()
        sleep(1)
        app.typeText("calendar")
        sleep(1)
        shot("D-S1-3-calendar")
        tap("Calendars")
        sleep(1)
        shot("D-S1-4-opened-calendars")
        back()
        pullDown()
        app.buttons["Search"].firstMatch.tap()
        sleep(1)
        app.typeText("pill")
        sleep(1)
        shot("D-S1-5-pill")
        app.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "HRV")
        sleep(1)
        shot("D-S1-6-hrv")
    }

    func test2QuickLog() {
        launch()
        let log = app.tabBars.buttons["Log"]
        log.press(forDuration: 1.2)
        sleep(1)
        shot("D-S2-1-menu")
        tap("Stress", scrolls: 0)
        shot("D-S2-2-stress-levels")
        tap("3, a bit stressed", scrolls: 0)
        sleep(1)
        shot("D-S2-3-logged-with-undo")
        sleep(5)
        app.tabBars.buttons["Body"].tap()
        sleep(1)
        log.press(forDuration: 1.2)
        sleep(1)
        tap("Latte", scrolls: 0)
        shot("D-S2-4-latte-from-body")
        // A plain tap still opens the full Log tab.
        log.tap()
        sleep(1)
        shot("D-S2-5-tap-opens-log")
    }

    func test3GuideAndBody() {
        launch()
        app.buttons["Health guide"].firstMatch.tap()
        sleep(1)
        shot("D-S3-2-guide-from-header")
        back()
        app.buttons["Settings and profile"].firstMatch.tap()
        sleep(1)
        shot("D-S3-3-settings-without-guide-row")
        back()
        app.tabBars.buttons["Body"].tap()
        sleep(1)
        shot("D-S4-1-body-summary")
        launch(appearance: "light")
        app.tabBars.buttons["Body"].tap()
        sleep(1)
        shot("D-S4-2-body-summary-light")
        launch(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        shot("D-S3-1-header-ax5")
        app.tabBars.buttons["Body"].tap()
        sleep(1)
        shot("D-S4-3-body-summary-ax5")
    }

    func test4HelloCard() {
        launch(["-demoHelloCard", "-demoClock", "10:23"])
        shot("D-T7-1-card")
        tap("Add a widget", scrolls: 0)
        sleep(1)
        shot("D-T7-2-widget-sheet")
        tap("Done", scrolls: 0)
        tap("Open it on your Watch", scrolls: 0)
        sleep(1)
        shot("D-T7-3-watch-sheet")
        tap("Done", scrolls: 0)
        tap("Got it", scrolls: 2)
        sleep(1)
        shot("D-T7-4-dismissed")
        launch(["-demoHelloCard"], appearance: "light")
        shot("D-T7-5-card-light")
        launch(["-demoHelloCard"], textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("D-T7-6-card-ax5")
    }

    /// Setup to its last step; the reading step's frames, then Today.
    private func onboardToReading(_ prefix: String) {
        tap("Connect Apple Health")
        tap("Natural cycle")
        tap("Continue")
        tap("Continue")
        tap("Start tracking")
        for i in 1...4 {
            shot("\(prefix)-\(i)")
            usleep(700_000)
        }
        sleep(3)
        shot("\(prefix)-5-today")
    }

    /// Opens a screen through search (D-S1).
    private func open(_ query: String, _ title: String) {
        pullDown()
        app.buttons["Search"].firstMatch.tap()
        sleep(1)
        app.typeText(query)
        sleep(1)
        tap(title, scrolls: 0)
        sleep(1)
    }

    func test6EmptyStates() {
        launch()
        open("exams", "Exams")
        shot("D-L2-1-exams")
        back()
        open("alcohol", "Alcohol")
        tap("Logged alcohol")
        sleep(1)
        shot("D-L2-2-alcohol")
        back()
        open("stress", "Stress")
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("D-L2-3-stress-no-empty-week")
    }

    func test5Onboarding() {
        launch(["-demoReading"], cycle: false)
        onboardToReading("D-L3-found")
        launch(cycle: false)
        onboardToReading("D-L3-nothing-yet")
    }
}
