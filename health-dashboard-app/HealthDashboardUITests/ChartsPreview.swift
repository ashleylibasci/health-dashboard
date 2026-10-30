import XCTest

/// Preview screenshots of the trend charts (D-G2 range picker, D-G3 break
/// weeks, D-G4 compare) on example data.
/// `SHOT_DIR=/folder xcodebuild test … -only-testing:HealthDashboardUITests/ChartsPreview`.
final class ChartsPreview: XCTestCase {
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

    /// The first hittable button whose label starts with `text`, scrolling to find it.
    @discardableResult
    private func tap(_ text: String, scrolls: Int = 6) -> Bool {
        let q = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text))
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

    /// The chart whose VoiceOver summary starts with `text`, scrolled into view.
    private func chart(_ text: String) -> XCUIElement {
        let el = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
        for _ in 0..<6 where !(el.exists && el.isHittable) { app.swipeUp(velocity: .slow) }
        return el
    }

    /// Taps a chart at a fraction of its width, as a finger would.
    private func touch(_ el: XCUIElement, at x: Double) {
        el.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
        sleep(1)
    }

    private func range(_ spoken: String) {
        app.buttons[spoken].firstMatch.tap()
        sleep(2)
    }


    /// Scrolls the trend card into view on a heart screen.
    private func heart(_ screen: String, appearance: String = "dark", textSize: String? = nil) {
        launch(["-demoOpen", screen], appearance: appearance, textSize: textSize)
        app.swipeUp(velocity: .slow)
        sleep(1)
    }

    func test1HeartRanges() {
        heart("hrv")
        shot("hrv-month")
        range("Week")
        shot("hrv-week")
        range("6 months")
        shot("hrv-6months")
        touch(chart("HRV, "), at: 0.45)
        shot("hrv-6months-week")
        range("Month")
        touch(chart("HRV, "), at: 0.62)
        shot("hrv-month-night")
    }

    func test2SleepHistory() {
        launch(["-demoOpen", "sleepHistory"])
        shot("sleep-week")
        range("Month")
        shot("sleep-month")
        range("6 months")
        shot("sleep-6months")
        range("Week")
    }

    func test3Compare() {
        heart("hrv")
        tap("Compare with Resting heart rate")
        shot("compare-rhr")
        touch(chart("HRV, "), at: 0.5)
        shot("compare-rhr-night")
        tap("Compare with Sleep")
        shot("compare-sleep")
        tap("Compare with Sleep")
        shot("compare-off")
        heart("restingHR")
        tap("Compare with HRV")
        shot("compare-restingHR-hrv")
    }

    func test4LightAndLargeText() {
        heart("hrv", appearance: "light")
        shot("hrv-light")
        heart("hrv", textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("hrv-ax5")
    }

    /// Prints each screen's element tree, to read the charts' one-sentence
    /// VoiceOver summaries (D-A2) in the log.
    func test5VoiceOverSummaries() {
        for screen in ["hrv", "sleepHistory", "recovery"] {
            launch(["-demoOpen", screen])
            app.swipeUp(velocity: .slow)
            sleep(1)
            print("TREE[\(screen)]\n" + app.debugDescription)
        }
    }
}
