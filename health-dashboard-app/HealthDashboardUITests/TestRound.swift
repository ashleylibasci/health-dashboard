import XCTest

/// Hands-on test round in the simulator: walks the app and saves a screenshot
/// (and the on-screen element tree) at each step.
///
/// Run with `TEST_RUNNER_SHOT_DIR=/some/folder xcodebuild test …`; without
/// SHOT_DIR the screenshots are only attached to the test result. Tests run in
/// name order and share the app's saved state, so `test1Onboarding` sets the
/// app up for the rest.
final class TestRound: XCTestCase {
    var app: XCUIApplication!
    var prefix = ""

    static let largestText = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() {
        continueAfterFailure = true
    }

    /// Launch in the given look and text size.
    func launch(appearance: String = "dark", textSize: String? = nil, args: [String] = []) {
        app = XCUIApplication()
        // Demo mode: example data, and Apple Health is never asked.
        app.launchArguments += ["-demo", "-appearance", appearance] + args
        // Extra demo arguments for the whole run, e.g. a tester's cycle setup:
        // TEST_RUNNER_DEMO_ARGS='-resetData -demoCycle irregular'.
        if let extra = ProcessInfo.processInfo.environment["DEMO_ARGS"] {
            app.launchArguments += Self.splitArgs(extra)
        }
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
    }

    /// Splits on spaces; single quotes keep a value with spaces together.
    static func splitArgs(_ s: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        for ch in s {
            if ch == "'" { quoted.toggle() } else if ch == " " && !quoted {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else { cur.append(ch) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = prefix + name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] else { return }
        let base = URL(fileURLWithPath: dir).appendingPathComponent(prefix + name)
        try? image.pngRepresentation.write(to: base.appendingPathExtension("png"))
        try? app.debugDescription.write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
    }

    /// The first hittable element whose label starts with `text`, scrolling down to find it.
    @discardableResult
    func tap(_ text: String, in query: XCUIElementQuery? = nil, scrolls: Int = 6) -> Bool {
        let q = (query ?? app.descendants(matching: .any))
            .matching(NSPredicate(format: "label BEGINSWITH %@", text))
        // Look down the page first, then back up (after a full-page screenshot
        // the page sits at the bottom).
        for i in 0...(scrolls * 2 + 1) {
            let el = q.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
            if let el { el.tap(); return true }
            if i < scrolls { app.swipeUp() } else { app.swipeDown() }
        }
        XCTFail("Couldn't find \(text)")
        return false
    }

    /// Picks an item in an open menu, scrolling the menu (not the page) to it.
    func pickMenuItem(_ text: String) {
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
        // Swipe on a visible item of the same menu.
        let prefix = String(text.prefix { $0 != " " })
        for _ in 0..<8 where !(item.exists && item.isHittable) {
            let visible = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix + " "))
                .allElementsBoundByIndex.filter { $0.isHittable }
            guard let handle = visible.dropFirst(visible.count / 2).first else { break }
            handle.swipeUp(velocity: .slow)
        }
        if item.exists, item.isHittable { item.tap() } else { XCTFail("No menu item \(text)") }
    }

    /// Screenshot the whole scrolling page, top to bottom.
    func shotPage(_ name: String, maxPages: Int = 8) {
        var last = Data()
        for i in 0..<maxPages {
            let png = XCUIScreen.main.screenshot().pngRepresentation
            if png == last { break }   // the page stopped scrolling
            last = png
            shot("\(name)-\(i)")
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
    }

    /// The Apple Health permission sheet: "Select All", then "Allow".
    func approveHealthSheet() {
        let sheet = app.staticTexts["Health Access"]
        guard sheet.waitForExistence(timeout: 5) else { return }
        // The sheet's buttons report off-screen frames; their text labels
        // don't, so tap the visible text by coordinate.
        let screen = app.windows.firstMatch.frame
        func tapVisible(_ label: String, below y: CGFloat = 0) -> Bool {
            let el = app.staticTexts.matching(NSPredicate(format: "label == %@", label))
                .allElementsBoundByIndex
                .first { screen.contains($0.frame) && $0.frame.minY > y }
            el?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return el != nil
        }
        _ = tapVisible("Select All 16 Topics") || tapVisible("Turn On All")
        sleep(1)
        // Then Allow/Continue, and on iOS 27 "how much history": all of it.
        // Every page of the sheet has "Don't Allow"; the app never does.
        let open = app.buttons["Don\u{2019}t Allow"]
        for _ in 0..<12 where open.exists {
            if tapVisible("All Recorded Data and Future Data") { sleep(1) }
            if tapVisible("Continue", below: screen.height / 2) || tapVisible("Allow", below: screen.height / 2) {
                sleep(2)
            } else {
                app.swipeUp()
            }
        }
        XCTAssertFalse(open.exists, "Health sheet still open")
    }

    // MARK: Onboarding

    func test1Onboarding() {
        prefix = "dark-onb-"
        launch(args: ["-resetData"])
        shot("1-welcome")
        tap("Connect Apple Health")
        sleep(1)
        shot("2-about")
        tap("Continue")
        shot("3-cycle")
        tap("Birth control")
        tap("Continue")
        shot("4-birth-control")
        tap("Combined pill")
        shot("4b-picked")
        tap("Continue")
        shot("5-pack")
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today is'")).firstMatch
        if picker.waitForExistence(timeout: 3) {
            picker.tap()
            sleep(1)
            shot("5b-pack-menu")
            pickMenuItem("Pill 18")
            sleep(1)
            shot("5c-pack-set")
        } else {
            XCTFail("No pack day picker")
        }
        tap("Continue")
        shot("6-conditions")
        tap("Continue")
        shot("7-sleep")
        tap("Continue")
        shot("8-prefs")
        tap("Start learning my normal")
        sleep(2)
        // Notification permission.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 3) { springboard.buttons["Allow"].tap() }
        sleep(2)
        shot("9-first-screen")
    }

    /// A beginner's first run at the largest text size: natural cycle, no
    /// conditions, every screen of setup page by page.
    func test0OnboardingBeginner() {
        prefix = "xxxl-onb-"
        launch(textSize: Self.largestText, args: ["-resetData"])
        shotPage("1-welcome", maxPages: 3)
        tap("Connect Apple Health")
        sleep(1)
        shotPage("2-about", maxPages: 3)
        tap("Continue")
        shotPage("3-cycle", maxPages: 4)
        tap("Natural cycle")
        shot("3b-picked")
        tap("Continue")
        shotPage("4-conditions", maxPages: 6)
        tap("Continue")
        shotPage("5-sleep", maxPages: 5)
        tap("Continue")
        shotPage("6-prefs", maxPages: 5)
        tap("Start learning my normal")
        sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 3) { springboard.buttons["Allow"].tap() }
        sleep(2)
        shotPage("7-first-today", maxPages: 4)
        goTab("Log")
        shotPage("8-first-log", maxPages: 6)
    }

    // MARK: Tabs

    func walkTabs(appearance: String, textSize: String? = nil, tag: String) {
        prefix = "\(tag)-"
        launch(appearance: appearance, textSize: textSize)
        sleep(2)
        for tab in ["Today", "Sleep", "Body", "Log"] {
            app.tabBars.buttons[tab].tap()
            sleep(1)
            shotPage(tab.lowercased())
            // Back to the top for the next visit.
            app.tabBars.buttons[tab].tap()
        }
    }

    func test2TabsDark() { walkTabs(appearance: "dark", tag: "dark") }
    func test3TabsLight() { walkTabs(appearance: "light", tag: "light") }
    func test4TabsLargestText() { walkTabs(appearance: "dark", textSize: Self.largestText, tag: "xxxl") }

    // MARK: Interactions

    func goTab(_ tab: String) {
        app.tabBars.buttons[tab].tap()
        app.tabBars.buttons[tab].tap()   // back to the root of that tab
        sleep(1)
    }

    func back() {
        let b = app.navigationBars.buttons.firstMatch
        if b.exists { b.tap() } else { app.swipeRight() }
        sleep(1)
    }

    /// Drag sideways along a chart, then tap two points, screenshotting each.
    func scrub(_ chart: XCUIElement, name: String) {
        guard chart.waitForExistence(timeout: 3) else { XCTFail("No chart for \(name)"); return }
        if !chart.isHittable { app.swipeUp(velocity: .slow) }
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let end = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        shot("\(name)-after-drag")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).tap()
        shot("\(name)-tap-left")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        shot("\(name)-tap-right")
        // A vertical drag on the chart should scroll the page, not scrub.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            .press(forDuration: 0.05, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.5)))
        shot("\(name)-vertical-drag")
    }

    func interactions(appearance: String, textSize: String? = nil, tag: String) {
        prefix = "\(tag)-act-"
        launch(appearance: appearance, textSize: textSize)
        sleep(2)

        // Pack setting: Settings → Your pack. Only pack methods have one
        // (the default setup, and -demoCycle pill).
        let demoArgs = ProcessInfo.processInfo.environment["DEMO_ARGS"] ?? ""
        if !demoArgs.contains("-demoCycle") || demoArgs.contains("-demoCycle pill") {
            goTab("Body")
            tap("Settings")
            tap("Pack type")
            shot("pack-1-settings")
            let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today is'")).firstMatch
            if picker.waitForExistence(timeout: 3) {
                picker.tap(); sleep(1)
                shot("pack-2-menu")
                pickMenuItem("Pill 25"); sleep(1)
                shot("pack-3-set-placebo")
            }
            let p24 = app.buttons["24 + 4"]
            if p24.exists { p24.tap(); sleep(1); shot("pack-4-type-24-4") }
            let p21 = app.buttons["21 + 7"]
            if p21.exists { p21.tap(); sleep(1) }
            if picker.exists { picker.tap(); sleep(1); pickMenuItem("Pill 18"); sleep(1) }
            back()
            // The Cycle screen after the change.
            tap("Cycle")
            sleep(1)
            shotPage("cycle", maxPages: 4)
            back()
        }

        // Coffee at a custom time: Log → "Pick another time" → 8:15 → a drink.
        goTab("Log")
        let timePicker = app.datePickers.firstMatch
        if timePicker.waitForExistence(timeout: 3) {
            timePicker.tap(); sleep(1)
            shot("coffee-1-picker")
            let wheels = app.pickerWheels
            if wheels.count >= 2 {
                wheels.element(boundBy: 0).adjust(toPickerWheelValue: "8")
                wheels.element(boundBy: 1).adjust(toPickerWheelValue: "15")
                if wheels.count >= 3 { wheels.element(boundBy: 2).adjust(toPickerWheelValue: "AM") }
            }
            shot("coffee-2-picked")
            // Close the popover by tapping the header.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap(); sleep(1)
        } else {
            XCTFail("No time picker on Log")
        }
        shot("coffee-3-before-log")
        let drink = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'latte' OR label CONTAINS[c] 'coffee'")).firstMatch
        if drink.exists { drink.tap() } else { XCTFail("No coffee button") }
        sleep(1)
        shot("coffee-4-logged")
        goTab("Today")
        tap("Caffeine")
        sleep(1)
        shotPage("caffeine", maxPages: 5)
        back()

        // Water.
        goTab("Today")
        let water = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Water:'")).firstMatch
        for _ in 0..<5 where !(water.exists && water.isHittable) { app.swipeUp(velocity: .slow) }
        shot("water-1-today-tile")
        let addBottle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add one bottle'")).firstMatch
        if addBottle.exists, addBottle.isHittable { addBottle.tap(); sleep(1); shot("water-2-added-from-today") }
        if water.exists { water.tap() }
        sleep(1)
        shotPage("water", maxPages: 5)
        back()

        // Energy chart: Body → Energy left → drag along the curve.
        goTab("Body")
        tap("Energy left")
        sleep(1)
        shot("energy-0")
        let curve = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ': peak '")).firstMatch
        scrub(curve, name: "energy-curve")
        let bank = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Energy left: charged'")).firstMatch
        for _ in 0..<4 where !(bank.exists && bank.isHittable) { app.swipeUp(velocity: .slow) }
        if bank.exists { scrub(bank, name: "energy-bank") }
        app.swipeDown(); app.swipeDown()
        shotPage("energy", maxPages: 6)
    }

    func test5InteractionsDark() { interactions(appearance: "dark", tag: "dark") }
    func test6InteractionsLight() { interactions(appearance: "light", tag: "light") }
    func test7InteractionsLargestText() { interactions(appearance: "dark", textSize: Self.largestText, tag: "xxxl") }

    // MARK: Main screens behind the tabs

    func mainScreens(appearance: String, textSize: String? = nil, tag: String) {
        prefix = "\(tag)-scr-"
        launch(appearance: appearance, textSize: textSize)
        sleep(2)
        // The Body tab's rows (stress and sleep stages live on Today and Sleep).
        for tile in ["Cycle", "Body clock", "HRV", "Resting HR", "Breathing", "Your week", "Streaks", "Fitness"] {
            goTab("Body")
            guard tap(tile) else { continue }
            sleep(1)
            shotPage(tile.lowercased().replacingOccurrences(of: " ", with: "-"), maxPages: 4)
        }
        goTab("Body")
        tap("Settings")
        shotPage("settings", maxPages: 8)
        goTab("Today")
        for link in ["Stress", "Why do I feel off?", "Getting accurate numbers"] {
            goTab("Today")
            guard tap(link) else { continue }
            sleep(1)
            shotPage(link.prefix(12).lowercased().replacingOccurrences(of: " ", with: "-"), maxPages: 3)
        }
    }

    func test8ScreensDark() { mainScreens(appearance: "dark", tag: "dark") }
    func test9ScreensLight() { mainScreens(appearance: "light", tag: "light") }
    func testZScreensLargestText() { mainScreens(appearance: "dark", textSize: Self.largestText, tag: "xxxl") }
}
