import XCTest

/// Preview screenshots of the motion ideas (D-M1 zoom, D-M3 logging, D-M4
/// charts drawing in, D-M5 the pinned answer, D-M6 evening dim) and the
/// Sky theme, on example data. Motion is caught in a few frames with
/// animations slowed down (`-UIAnimationDragCoefficient`).
/// `SHOT_DIR=/folder xcodebuild test … -only-testing:HealthDashboardUITests/MotionPreview`.
final class MotionPreview: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ args: [String] = [], appearance: String = "dark", textSize: String? = nil, slow: Int? = nil) {
        app = XCUIApplication()
        app.launchArguments += ["-appearance", appearance, "-resetData", "-demoCycle", "pill"] + args
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        if let slow { app.launchArguments += ["-UIAnimationDragCoefficient", "\(slow)"] }
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

    /// Frames of whatever is moving: one now, then every `gap` seconds.
    private func frames(_ name: String, count: Int = 4, gap: Double = 0.35) {
        for i in 1...count {
            shot("\(name)-\(i)")
            if i < count { Thread.sleep(forTimeInterval: gap) }
        }
    }

    /// The first hittable element whose label starts with `text`, scrolling to find it.
    @discardableResult
    private func element(_ text: String, scrolls: Int = 6) -> XCUIElement? {
        let q = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text))
        for i in 0...(scrolls * 2 + 1) {
            if let el = q.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { return el }
            if i < scrolls { app.swipeUp() } else { app.swipeDown() }
        }
        XCTFail("Couldn't find \(text)")
        return nil
    }

    private func tap(_ text: String) {
        element(text)?.tap()
        sleep(1)
    }

    // MARK: D-M3

    /// Scrolls the Log tab to the water card while `-demoLog` logs a latte,
    /// then bottles up to the goal; the frames come from a screen
    /// recording made alongside.
    func testM3Logging() {
        launch(["-demoTab", "log", "-demoLog"])
        app.swipeUp(velocity: .slow)
        sleep(30)
        shot("D-M3-end")
    }

    // MARK: D-M4

    /// HRV's trend drawing in, then switching ranges; Energy's Score and
    /// Energy left. Frames come from a screen recording made alongside.
    func testM4Charts() {
        launch(["-demoOpen", "hrv"])
        sleep(2)
        app.buttons["Week"].firstMatch.tap()
        sleep(2)
        app.buttons["6 months"].firstMatch.tap()
        sleep(2)
        shot("D-M4-hrv-6months")
        launch(["-demoOpen", "energy"])
        sleep(2)
        app.buttons["Energy left"].firstMatch.tap()
        sleep(2)
        app.buttons["Score"].firstMatch.tap()
        sleep(2)
        shot("D-M4-energy-score")
    }

    // MARK: D-M5

    /// The answer joining the title as Recovery's summary scrolls away,
    /// and leaving when it comes back; HRV at the largest text size.
    func testM5PinnedAnswer() {
        launch(["-demoOpen", "recovery"])
        shot("D-M5-1")
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("D-M5-2")
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("D-M5-3")
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        sleep(1)
        shot("D-M5-4")
        launch(["-demoOpen", "hrv"], textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.swipeUp(velocity: .slow)
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("D-M5-5-AX5")
    }

    // MARK: D-M6

    func testM6EveningDim() {
        launch(["-demoClock", "22:15", "-eveningDim", "NO"])
        shot("D-M6-1-dark-off")
        launch(["-demoClock", "22:15", "-demoEveningDim"])
        shot("D-M6-2-dark-dim")
        launch(["-demoClock", "22:15", "-eveningDim", "NO"], appearance: "light")
        shot("D-M6-3-light-off")
        launch(["-demoClock", "22:15", "-demoEveningDim"], appearance: "light")
        shot("D-M6-4-light-dim")
    }
}
