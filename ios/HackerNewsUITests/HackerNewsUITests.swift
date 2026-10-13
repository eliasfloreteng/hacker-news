//
//  HackerNewsUITests.swift
//  HackerNewsUITests
//

import XCTest

final class HackerNewsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Opens comments for the first story and collapses the first comment,
    /// capturing screenshots so the threaded view + collapse behaviour can be
    /// inspected.
    @MainActor
    func testCommentsAndCollapse() throws {
        let app = XCUIApplication()
        app.launch()

        let firstComments = app.buttons["commentsLink"].firstMatch
        XCTAssertTrue(firstComments.waitForExistence(timeout: 25), "Top stories should load")
        firstComments.tap()

        XCTAssertTrue(app.navigationBars["Comments"].waitForExistence(timeout: 25),
                      "Comments screen should open")

        // Wait for comment rows to load.
        let firstComment = app.buttons["comment"].firstMatch
        XCTAssertTrue(firstComment.waitForExistence(timeout: 25), "Comments should load")
        sleep(3) // allow nested replies to fetch
        attach(app, "01-comments-expanded")

        // Collapse the first (top-level) comment: its replies hide, the comment stays.
        firstComment.tap()
        sleep(1)
        attach(app, "02-comments-collapsed")

        // The story header stays pinned while the comments scroll under it.
        let title = app.buttons["storyTitle"]
        XCTAssertTrue(title.exists)
        let pinnedFrame = title.frame
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        attach(app, "03-comments-scrolled")
        XCTAssertTrue(title.isHittable, "Story title should stay on screen")
        XCTAssertEqual(title.frame, pinnedFrame, "Story title should not scroll away")
    }

    /// With points, author and comments hidden the rows go compact and lose
    /// the comments button, so tapping the row itself has to open the thread.
    @MainActor
    func testCompactRowOpensComments() throws {
        let app = XCUIApplication()
        // Launch arguments land in UserDefaults' argument domain, overriding
        // the stored settings for this run only.
        app.launchArguments += ["-hidePoints", "YES", "-hideAuthor", "YES", "-hideComments", "YES"]
        app.launch()

        let source = app.staticTexts["storySource"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 25), "Top stories should load")
        XCTAssertFalse(app.buttons["commentsLink"].exists, "Comments button should be hidden")
        attach(app, "04-compact-list")

        // Below the title, which opens the article instead.
        source.tap()
        XCTAssertTrue(app.navigationBars["Comments"].waitForExistence(timeout: 10),
                      "Tapping the row should open comments")
    }
}
