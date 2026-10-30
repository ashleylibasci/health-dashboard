import XCTest

/// Preview screenshots of the insights ideas (Patterns, the week story,
/// check-in tags, At a glance tiles, alcohol's colour, notification
/// settings), on example data.
/// `TEST_RUNNER_SHOT_DIR=/folder xcodebuild test … -only-testing:HealthDashboardUITests/InsightsPreview`.
final class InsightsPreview: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ args: [String], appearance: String = "dark", textSize: String? = nil) {
        app = XCUIApplication()
        app.launchArguments += ["-demo", "-appearance", appearance, "-resetData", "-demoCycle", "pill", "-demoPatterns"] + args
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

    /// The "History" link of the Log section whose card starts with `card`.
    private func openHistory(above card: String) {
        scroll(to: card)
        let anchor = app.staticTexts[card].firstMatch
        let links = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'")).allElementsBoundByIndex
            .filter { $0.isHittable && $0.frame.maxY <= anchor.frame.minY }
        links.max { $0.frame.minY < $1.frame.minY }?.tap()
        sleep(1)
    }

    private func openCheckIn() {
        app.tabBars.buttons["Log"].tap()
        sleep(1)
        tap("Morning check-in")
    }

    func testP3CheckInTags() {
        launch([])
        openCheckIn()
        tap("4, Good")
        scroll(to: "Anything going on?")
        tap("Studied late")
        tap("Exam today")
        scroll(to: "Patterns")
        shot("D-P3-check-in-tags")
    }

    func testP2Patterns() {
        launch([])
        openCheckIn()
        tap("Patterns")
        shot("D-P2-patterns")
        tap("Exam weeks")
        shot("D-P2-pattern-open")
        scroll(to: "Still counting")
        shot("D-P2-still-counting")
    }

    /// Through Sleep → Learning you, for after midnight (the check-in waits
    /// for the morning then) and the hour before bed (Today never idles).
    func testP2PatternsFromLearning() {
        launch(["-demoOpen", "recovery"])
        app.tabBars.buttons["Sleep"].tap()
        sleep(1)
        tap("Learning you")
        tap("Patterns")
        shot("D-P2-patterns")
        tap("Exam weeks")
        shot("D-P2-pattern-open")
        scroll(to: "Still counting")
        tap("Parties")
        shot("D-P2-still-counting")
    }

    func testP2PatternsLight() {
        launch(["-demoOpen", "recovery"], appearance: "light")
        app.tabBars.buttons["Sleep"].tap()
        sleep(1)
        tap("Learning you")
        tap("Patterns")
        shot("D-P2-patterns-light")
    }

    func testP5Alcohol() {
        launch(["-demoFuel"])
        app.tabBars.buttons["Log"].tap()
        sleep(1)
        scroll(to: "Tap what you had")
        shot("D-P5-log-alcohol")
        openHistory(above: "Tap what you had")
        shot("D-P5-alcohol-screen")
        scroll(to: "Your recent nights")
        shot("D-P5-alcohol-chart")
    }

    func testP5AlcoholLight() {
        launch(["-demoFuel"], appearance: "light")
        app.tabBars.buttons["Log"].tap()
        sleep(1)
        openHistory(above: "Tap what you had")
        scroll(to: "Your recent nights")
        shot("D-P5-alcohol-chart-light")
    }

    func testP1WeekStory() {
        launch(["-demoWeekStory", "-demoClock", "18:30"])
        scroll(to: "Your week")
        shot("D-P1-today-new")
        tap("Your week")
        sleep(1)
        shot("D-P1-1-best-night")
        for (i, name) in ["2-energy", "3-caffeine", "4-pack-week", "5-one-thing"].enumerated() {
            app.swipeLeft()
            sleep(1)
            shot("D-P1-\(name)")
            _ = i
        }
    }

    func testP1WeekStoryLightAndLargeText() {
        launch([], appearance: "light")
        tap("Your week")
        sleep(1)
        shot("D-P1-1-best-night-light")
        launch([], textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        tap("Your week")
        sleep(1)
        shot("D-P1-1-best-night-ax5")
    }

    func testP4Tiles() {
        launch(["-demoClock", "09:30"])
        scroll(to: "At a glance")
        app.swipeUp(velocity: .slow)
        sleep(1)
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Caffeine'")).firstMatch
        tile.press(forDuration: 1.2)
        sleep(1)
        shot("D-P4-1-long-press")
        tap("Edit tiles")
        sleep(1)
        shot("D-P4-2-editor")
        tap("Add Pill")
        tap("Remove Stress")
        shot("D-P4-3-editor-changed")
        tap("Done")
        sleep(1)
        shot("D-P4-4-today-pinned")
    }

    func testP4TilesPinnedLarge() {
        launch(["-demoTiles", "pill,energy,caffeine", "-demoClock", "09:30"], textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        scroll(to: "Pill")
        shot("D-P4-pinned-ax5")
    }

    // MARK: Notifications

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func allowNotificationsIfAsked() {
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 6) { allow.tap() }
    }

    /// Waits on the Home Screen for a banner containing `text`, shoots it,
    /// then long-presses it to show its buttons and shoots that.
    private func shootNotification(containing text: String, _ name: String) {
        XCUIDevice.shared.press(.home)
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        guard banner.waitForExistence(timeout: 40) else { XCTFail("No notification with \(text)"); return }
        shot("\(name)-1-banner")
        banner.press(forDuration: 1.5)
        sleep(2)
        shot("\(name)-2-buttons")
    }

    /// Closes a notification left open by `shootNotification`.
    private func closeNotification() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        sleep(1)
    }

    func testN1MorningNote() {
        launch(["-demoMorningNote"])
        allowNotificationsIfAsked()
        shootNotification(containing: "Take it steady", "D-N1-morning-note")
        springboard.buttons["+1 bottle"].tap()
        sleep(3)
        app.activate()
        sleep(2)
        scroll(to: "Water")
        shot("D-N1-morning-note-3-bottle-logged")
    }

    func testN2BedtimeNudge() {
        launch(["-demoBedtimeNudge"])
        allowNotificationsIfAsked()
        shootNotification(containing: "Lights low", "D-N2-bedtime-nudge")
        closeNotification()
    }

    /// Starts on Body (with `-demoOpen`), so Today's live bedtime countdown
    /// never keeps the app from idling in the hour before bed.
    private func openSettingsFromBody() {
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 5) { back.tap() }
        sleep(1)
        app.buttons["Settings and profile"].firstMatch.tap()
        sleep(1)
    }

    func testN4NotificationSettings() {
        launch(["-demoOpen", "recovery"])
        openSettingsFromBody()
        scroll(to: "Notifications")
        shot("D-N4-1-settings-row")
        tap("Notifications")
        shot("D-N4-2-by-moment")
        launch(["-demoOpen", "recovery"], appearance: "light")
        openSettingsFromBody()
        tap("Notifications")
        shot("D-N4-3-by-moment-light")
    }

    // MARK: Today idles

    /// In the half hour before bed Today shows "Bed in 20 min". It must
    /// still go idle, or every XCUITest step there waits ~15 minutes.
    func testTodayIdlesBeforeBed() {
        launch(["-demoClock", "23:20"])
        let start = Date()
        app.tabBars.buttons["Sleep"].tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertLessThan(Date().timeIntervalSince(start), 30, "Today didn't go idle")
        scroll(to: "Bed in")
        shot("today-idle-before-bed")
    }
}
