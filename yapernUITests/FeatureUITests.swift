import XCTest

@MainActor
final class FeatureUITests: XCTestCase {
    func testSignInProfileAndSignOut() {
        let app = launch()
        app.buttons.matching(identifier: "Account").firstMatch.tap()
        app.buttons["account.signin"].tap()
        signIn(app)
        let name = app.textFields["account.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let original = name.value as? String ?? ""
        name.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -1, dy: 0)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + "Alex Updated")
        app.buttons["account.save"].tap()
        XCTAssertTrue(app.staticTexts["Name saved."].waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Alex Updated")
        screenshot("Account")
        app.buttons["account.signout"].tap()
        app.sheets.buttons["Sign out"].tap()
        XCTAssertTrue(app.buttons["account.signin"].waitForExistence(timeout: 5))
    }

    func testPostReplyAndDeleteOwnedMessage() {
        let app = launch(signedIn: true)
        XCTAssertTrue(app.buttons["feed.compose"].waitForExistence(timeout: 5))
        app.buttons["feed.compose"].tap()
        app.buttons["compose.board"].tap()
        app.buttons["y/general"].tap()
        app.textFields["compose.title"].tap()
        app.textFields["compose.title"].typeText("A new iOS message")
        app.textFields["compose.body"].tap()
        app.textFields["compose.body"].typeText("Posted from the native composer.")
        app.buttons["compose.post"].tap()
        XCTAssertTrue(app.staticTexts["A new iOS message"].waitForExistence(timeout: 5))
        app.buttons["detail.reply"].tap()
        let reply = app.textFields["reply.body"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        reply.typeText("A native reply")
        app.buttons["reply.post"].tap()
        XCTAssertTrue(app.staticTexts["A native reply"].waitForExistence(timeout: 5))
        screenshot("Message and reply")
        app.buttons["detail.actions"].tap()
        app.buttons["Delete message"].tap()
        app.sheets.buttons["Delete message"].tap()
        XCTAssertTrue(app.buttons["feed.compose"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["A new iOS message"].exists)
    }

    func testSearchBoardsAndCreateBoard() {
        let app = launch(signedIn: true)
        app.buttons.matching(identifier: "Sub-yaps").firstMatch.tap()
        XCTAssertTrue(app.buttons["boards.general"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        if !search.exists { app.buttons["Search"].tap() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Apps")
        XCTAssertTrue(app.buttons["boards.apps"].exists)
        XCTAssertFalse(app.buttons["boards.general"].exists)
        search.typeText("\n")
        app.buttons["boards.create"].tap()
        app.textFields["board.name"].tap()
        app.textFields["board.name"].typeText("Native Apps")
        app.textFields["board.description"].tap()
        app.textFields["board.description"].typeText("A place for native app conversations.")
        app.buttons["board.create"].tap()
        XCTAssertTrue(app.staticTexts["No messages yet."].waitForExistence(timeout: 5))
        screenshot("New sub-yap")
    }

    func testBoardMessageDeletionUpdatesBothFeeds() {
        let app = launch(signedIn: true)
        app.buttons.matching(identifier: "Sub-yaps").firstMatch.tap()
        app.buttons["boards.general"].tap()
        let message = app.buttons["feed.message.message-0"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        message.tap()
        app.buttons["detail.actions"].tap()
        app.buttons["Delete message"].tap()
        app.sheets.buttons["Delete message"].tap()
        XCTAssertTrue(app.buttons["feed.compose"].waitForExistence(timeout: 5))
        XCTAssertFalse(message.exists)
        app.buttons.matching(identifier: "Messages").firstMatch.tap()
        XCTAssertFalse(message.exists)
    }

    func testExpiredSessionPreservesReplyDraft() {
        let app = launch(signedIn: true, arguments: ["--ui-expire-on-write"])
        let first = app.buttons["feed.message.message-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        app.buttons["detail.reply"].tap()
        let reply = app.textFields["reply.body"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        reply.typeText("Keep this draft")
        app.buttons["reply.post"].tap()
        XCTAssertTrue(app.buttons["Sign in to reply"].waitForExistence(timeout: 5))
        XCTAssertEqual(reply.value as? String, "Keep this draft")
        app.buttons["Sign in to reply"].tap()
        signIn(app)
        XCTAssertEqual(reply.value as? String, "Keep this draft")
        app.buttons["reply.post"].tap()
        XCTAssertTrue(app.staticTexts["Keep this draft"].waitForExistence(timeout: 5))
    }

    func testLinkPreviewFailureStillAllowsPosting() {
        let app = launch(signedIn: true)
        app.buttons["feed.compose"].tap()
        app.buttons["compose.board"].tap()
        app.buttons["y/general"].tap()
        app.textFields["compose.title"].tap()
        app.textFields["compose.title"].typeText("A link from iOS")
        app.buttons["compose.addlink"].tap()
        let link = app.textFields["compose.link"]
        link.tap()
        link.typeText("https://example.com/article")
        XCTAssertTrue(app.buttons["compose.post"].isEnabled)
        screenshot("Link composer")
        app.buttons["compose.post"].tap()
        XCTAssertTrue(app.staticTexts["A link from iOS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["https://example.com/article"].exists)
    }

    func testBlogAndLegalPagesOpenInAppBrowser() {
        let app = launch()
        app.buttons.matching(identifier: "Account").firstMatch.tap()
        for title in ["Blog", "Privacy policy", "Terms of service"] {
            app.buttons[title].tap()
            let done = app.buttons["Close"]
            XCTAssertTrue(done.waitForExistence(timeout: 10))
            done.tap()
        }
    }

    func testOfflineStateAndSignedOutComposer() {
        let app = launch(arguments: ["--ui-offline"])
        XCTAssertTrue(app.staticTexts["Couldn’t load messages"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try again"].exists)
        screenshot("Offline feed")
        app.buttons["feed.compose"].tap()
        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["signin.submit"].isEnabled)
    }

    private func launch(signedIn: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (signedIn ? ["--ui-signed-in"] : []) + arguments
        app.launch()
        return app
    }

    private func signIn(_ app: XCUIApplication) {
        let email = app.textFields["signin.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("alex@example.com")
        app.secureTextFields["signin.password"].tap()
        app.secureTextFields["signin.password"].typeText("test password")
        XCTAssertTrue(app.buttons["signin.submit"].isEnabled)
        app.buttons["signin.submit"].tap()
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
