import XCTest

final class FeedUITests: XCTestCase {
    @MainActor
    func testLiveFeedDetailFilterAndScrolling() throws {
        let app = XCUIApplication()
        app.launch()

        let feed = app.scrollViews["feed.scroll"]
        XCTAssertTrue(feed.waitForExistence(timeout: 5))
        let titles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed.message."))
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 25), "Production feed should load")
        feed.swipeDown()
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 20))
        attachScreenshot("Latest messages")

        titles.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.share"].exists)
        XCTAssertTrue(app.staticTexts["Replies"].exists)
        attachScreenshot("Message detail")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["feed.filter"].tap()
        let general = app.buttons["General"]
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        general.tap()
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 20))
        attachScreenshot("Filtered messages")

        app.buttons["feed.filter"].tap()
        app.buttons["All sub-yaps"].tap()
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 20))
        let firstID = titles.firstMatch.identifier
        for _ in 0..<5 { feed.swipeUp() }
        XCTAssertFalse(app.buttons[firstID].isHittable)
        attachScreenshot("Scrolling messages")
    }

    @MainActor
    func testAccessibilityTextAndLandscapeLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let title = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed.message.")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 25))
        XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX)
        XCTAssertTrue(app.buttons["feed.filter"].isHittable)
        attachScreenshot("Accessibility text")

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX)
        attachScreenshot("Landscape")
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
