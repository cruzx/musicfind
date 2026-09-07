import XCTest
import SwiftUI
@testable import musicfind

@MainActor
final class PlayerRenderSupportTests: XCTestCase {
    func testPlaybackNotificationsPublishOnlyActualChanges() {
        let counts = playbackPublicationRegressionCounts()
        XCTAssertEqual(counts["initial"], 3)
        XCTAssertEqual(counts["duplicates"], 0)
        XCTAssertEqual(counts["enrichedDuplicates"], 0)
        for key in ["title", "artist", "lyrics", "color", "artwork", "backdrop", "pause", "resume", "backdropReuse", "backdropReplacement"] {
            XCTAssertEqual(counts[key], 1, key)
        }
        XCTAssertEqual(counts["track"], 2)
    }

    func testPillCPUReference() {
        measurePillCPU(reference: true)
    }

    func testPillCPUOptimized() {
        measurePillCPU(reference: false)
    }

    private func measurePillCPU(reference: Bool) {
        let host = UIHostingController(rootView: playerPillAnimationRegressionView(time: nil, color: .cyan, reference: reference))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 84))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTCPUMetric()], options: options) {
            RunLoop.main.run(until: Date().addingTimeInterval(3))
        }
        window.isHidden = true
        window.rootViewController = nil
    }

    func testRimAnimationPrecalculationPreservesAppearance() async {
        let cases = [
            (0.0, Color.cyan, CGSize(width: 360, height: 84)),
            (4.0, Color.green, CGSize(width: 360, height: 84)),
            (11.0, Color.pink, CGSize(width: 360, height: 84)),
            (0.0, Color.cyan, CGSize(width: 320, height: 53)),
            (4.0, Color.green, CGSize(width: 360, height: 53)),
            (11.0, Color.pink, CGSize(width: 430, height: 53)),
            (19.5, Color.orange, CGSize(width: 360, height: 53)),
            (37.0, Color.gray, CGSize(width: 360, height: 53))
        ]
        for (time, color, size) in cases {
            var samples: [[UInt8]] = []
            for reference in [true, false] {
                let host = UIHostingController(rootView: playerPillAnimationRegressionView(time: time, color: color, reference: reference, size: size))
                host.safeAreaRegions = []
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                host.view.layoutIfNeeded()
                try? await Task.sleep(for: .milliseconds(500))
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "rim-\(time)-\(size.width)x\(size.height)-\(reference ? "reference" : "optimized")"
                attachment.lifetime = .keepAlways
                add(attachment)
                if let cgImage = image.cgImage {
                    let count = cgImage.width * cgImage.height * 4
                    var bytes = [UInt8](repeating: 0, count: count)
                    bytes.withUnsafeMutableBytes { buffer in
                        let context = CGContext(data: buffer.baseAddress, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                    }
                    samples.append(bytes)
                }
                window.isHidden = true
                window.rootViewController = nil
            }
            XCTAssertEqual(samples.count, 2)
            guard samples.count == 2 else { continue }
            let differences = zip(samples[0], samples[1]).map { abs(Int($0) - Int($1)) }
            let mean = Double(differences.reduce(0, +)) / Double(differences.count)
            let largeDifferenceFraction = Double(differences.filter { $0 > 2 }.count) / Double(differences.count)
            let metrics = XCTAttachment(string: "Size \(size), phase \(time), mean channel error \(mean), large channel errors \(largeDifferenceFraction)")
            metrics.lifetime = .keepAlways
            add(metrics)
            XCTAssertLessThan(mean, 0.10, "Phase \(time), mean channel error \(mean)")
            XCTAssertLessThan(largeDifferenceFraction, 0.002, "Phase \(time), large channel errors \(largeDifferenceFraction)")
        }
    }

    func testPortraitAndLandscapeRender() async {
        let artwork = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 32, y: 32, width: 128, height: 128))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 200, y: 200, width: 180, height: 180))
        }
        for (name, size, lyric) in [
            ("portrait", CGSize(width: 370, height: 720), "A moment worth remembering"),
            ("landscape-long", CGSize(width: 852, height: 393), "A longer line of words that should stay inside the lyric region"),
            ("landscape-short", CGSize(width: 852, height: 393), "One moment")
        ] {
            let host = UIHostingController(rootView: playerRenderRegressionView(size: size, artwork: artwork, lyric: lyric))
            host.safeAreaRegions = []
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            host.view.backgroundColor = .black
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(800))
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            XCTAssertEqual(image.size, size)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            window.rootViewController = nil
        }
    }
}
