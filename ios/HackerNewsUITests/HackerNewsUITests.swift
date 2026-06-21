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
    }
}
