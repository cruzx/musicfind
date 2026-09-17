import XCTest

final class DuoHomeUITests: XCTestCase {
    @MainActor
    func testQueueSettingsAndDisablingDuoLayout() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--duo-home"]
        app.launch()
        let queue = app.buttons["duo-queue"]
        XCTAssertTrue(queue.waitForExistence(timeout: 30))
        queue.tap()
        let done = app.buttons["完成"]
        if !done.waitForExistence(timeout: 3) { queue.tap() }
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["播放队列"].exists)
        done.tap()
        app.buttons["duo-settings"].tap()
        let toggle = app.switches["duo-layout-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if !toggle.isHittable { app.swipeUp() }
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        app.buttons["返回首页"].tap()
        XCTAssertTrue(app.buttons["open-my-music"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["duo-settings"].exists)
    }
}
