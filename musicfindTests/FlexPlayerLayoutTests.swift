import XCTest
import SwiftUI
@testable import musicfind

final class FlexPlayerLayoutTests: XCTestCase {
    func testBookLayoutExcludesVerticalHinge() {
        let layout = DuoPaneLayout(size: CGSize(width: 900, height: 680), division: CGRect(x: 440, y: 0, width: 24, height: 680))
        XCTAssertTrue(layout.isBook)
        XCTAssertEqual(layout.player.maxX, 440)
        XCTAssertEqual(layout.queue.minX, 464)
        XCTAssertEqual(layout.queue.maxX, 900)
        XCTAssertFalse(layout.player.intersects(layout.queue))
    }

    func testTabletopLayoutExcludesHorizontalHinge() {
        let layout = DuoPaneLayout(size: CGSize(width: 680, height: 900), division: CGRect(x: 0, y: 430, width: 680, height: 32))
        XCTAssertFalse(layout.isBook)
        XCTAssertEqual(layout.player.maxY, 430)
        XCTAssertEqual(layout.queue.minY, 462)
        XCTAssertEqual(layout.queue.maxY, 900)
    }

    func testInvalidAndEdgeRegionsDoNotActivateFold() {
        let size = CGSize(width: 680, height: 900)
        for frame in [CGRect.zero, CGRect(x: 0, y: 900, width: 680, height: 20), CGRect(x: 50, y: 50, width: 20, height: 20), CGRect(x: CGFloat.nan, y: 0, width: 20, height: 900)] {
            XCTAssertNil(DuoPaneLayout.validDivision(frame, in: size))
        }
    }

    func testQueueViewportContainsFiveAndHalfSquareCovers() {
        for width: CGFloat in [320, 680, 900] {
            let metrics = DuoQueueMetrics(width: width)
            XCTAssertEqual(metrics.side * 5.5 + 8 * 5, width, accuracy: 0.001)
            XCTAssertEqual(metrics.leadingOffset(row: 1), -metrics.stride / 2)
            XCTAssertEqual(metrics.leadingOffset(row: 2), 0)
        }
    }

    @MainActor
    func testRenderCompactAndSquareLayouts() async throws {
        for size in [CGSize(width: 390, height: 780), CGSize(width: 800, height: 900)] {
            let host = UIHostingController(rootView: FlexPlayerPreview().environment(\.scenePhase, .active))
            host.safeAreaRegions = []
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "flex-\(Int(size.width))x\(Int(size.height))"
            attachment.lifetime = .keepAlways
            add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/flex-\(Int(size.width))x\(Int(size.height)).png"))
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testManualLayoutKeepsLandscapePlayerAndScrollableQueue() {
        for size in [CGSize(width: 390, height: 780), CGSize(width: 844, height: 340), CGSize(width: 800, height: 900)] {
            let layout = FlexPlayerLayout(size: size)
            XCTAssertGreaterThan(layout.queueHeight, 100)
            XCTAssertGreaterThan(size.width, layout.playerHeight)
            XCTAssertEqual(layout.playerHeight + layout.dividerHeight + layout.queueHeight, size.height, accuracy: 0.01)
        }
    }

    func testHorizontalReservedRegionIsExcludedFromBothPanes() {
        let layout = FlexPlayerLayout(size: CGSize(width: 800, height: 900), divisionFrame: CGRect(x: 0, y: 400, width: 800, height: 35))
        XCTAssertEqual(layout.playerHeight, 400)
        XCTAssertEqual(layout.dividerHeight, 35)
        XCTAssertEqual(layout.queueHeight, 465)
    }

    func testVerticalOrOutsideRegionDoesNotTriggerHorizontalSplit() {
        let size = CGSize(width: 800, height: 900)
        let expected = FlexPlayerLayout(size: size)
        for region in [CGRect(x: 395, y: 0, width: 10, height: 900), CGRect(x: 0, y: 920, width: 800, height: 20)] {
            XCTAssertEqual(FlexPlayerLayout(size: size, divisionFrame: region).playerHeight, expected.playerHeight)
        }
    }
}
