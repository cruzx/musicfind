import XCTest

final class FlexPlayerUITests: XCTestCase {
    @MainActor
    func testProductionEntryAndReturn() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let settings = app.buttons["open-my-music"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let entry = app.buttons["open-flex-player"]
        if !entry.waitForExistence(timeout: 2) { settings.tap() }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Production settings entry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        let close = app.buttons["close-flex-player"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    @MainActor
    func testQueueSelectionPauseScrollAndExit() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--flex-preview"]
        app.launch()
        let first = app.buttons["flex-song-91000"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertEqual(first.value as? String, "正在播放")
        first.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已暂停"), object: first)], timeout: 3), .completed)
        let second = app.buttons["flex-song-91001"]
        second.tap()
        XCTAssertEqual(second.value as? String, "正在播放")
        let bar = app.descendants(matching: .any)["bottom-player-song"].firstMatch
        XCTAssertTrue(bar.exists)
        XCTAssertEqual(bar.value as? String, "91001")
        bar.tap()
        XCTAssertEqual(second.value as? String, "已暂停")
        bar.tap()
        XCTAssertEqual(second.value as? String, "正在播放")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Flex player - upper lyrics, cover queue, floating bar"
        shot.lifetime = .keepAlways
        add(shot)
        app.scrollViews["flex-player-queue"].swipeUp()
        let last = app.buttons["flex-song-91019"]
        XCTAssertTrue(last.isHittable)
        last.tap()
        XCTAssertEqual(last.value as? String, "正在播放")
        app.buttons["close-flex-player"].tap()
        XCTAssertTrue(app.staticTexts["flex-preview-closed"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testEmptyQueueCanExit() {
        let app = XCUIApplication()
        app.launchArguments = ["--flex-preview", "--flex-empty"]
        app.launch()
        XCTAssertTrue(app.staticTexts["暂无播放队列"].waitForExistence(timeout: 15))
        app.buttons["close-flex-player"].tap()
        XCTAssertTrue(app.staticTexts["flex-preview-closed"].waitForExistence(timeout: 3))
    }
}
