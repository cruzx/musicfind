import SwiftUI

struct FlexPlayerLayout {
    let playerHeight: CGFloat
    let dividerHeight: CGFloat
    let queueHeight: CGFloat

    init(size: CGSize, divisionFrame: CGRect? = nil) {
        let height = max(0, size.height)
        // Only a horizontal region spanning this view can split it top/bottom.
        if let region = divisionFrame,
           region.width >= size.width * 0.9,
           region.width > region.height,
           region.minY > 0, region.maxY < height {
            playerHeight = region.minY
            dividerHeight = region.height
            queueHeight = height - region.maxY
        } else {
            // Manual preview: cap the upper pane to retain the landscape composition
            // even on a narrow, non-folding iPhone.
            dividerHeight = min(12, height)
            playerHeight = min((height - dividerHeight) / 2, max(0, size.width) * 0.62)
            queueHeight = height - dividerHeight - playerHeight
        }
    }
}

/// Frames are in the GeometryReader's local, safe-area-respecting coordinates.
struct DuoPaneLayout {
    let player: CGRect
    let queue: CGRect
    let isBook: Bool

    static func validDivision(_ frame: CGRect?, in size: CGSize) -> CGRect? {
        guard let frame, !frame.isNull, frame.width.isFinite, frame.height.isFinite,
              frame.minX.isFinite, frame.minY.isFinite, size.width > 0, size.height > 0 else { return nil }
        let horizontal = frame.width >= size.width * 0.9 && frame.width > frame.height
            && frame.minY > 0 && frame.maxY < size.height
        let vertical = frame.height >= size.height * 0.9 && frame.height > frame.width
            && frame.minX > 0 && frame.maxX < size.width
        return horizontal || vertical ? frame : nil
    }

    init(size: CGSize, division: CGRect?) {
        if let region = Self.validDivision(division, in: size) {
            isBook = region.height > region.width
            if isBook {
                player = CGRect(x: 0, y: 0, width: region.minX, height: size.height)
                queue = CGRect(x: region.maxX, y: 0, width: size.width - region.maxX, height: size.height)
            } else {
                player = CGRect(x: 0, y: 0, width: size.width, height: region.minY)
                queue = CGRect(x: 0, y: region.maxY, width: size.width, height: size.height - region.maxY)
            }
        } else {
            isBook = false
            let fallback = FlexPlayerLayout(size: size)
            player = CGRect(x: 0, y: 0, width: size.width, height: fallback.playerHeight)
            queue = CGRect(x: 0, y: fallback.playerHeight + fallback.dividerHeight, width: size.width, height: fallback.queueHeight)
        }
    }
}

enum DuoGeometry {
    static func division(in proxy: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).compactMap {
                DuoPaneLayout.validDivision($0.frame, in: proxy.size)
            }.first
        }
        return nil
    }
}

/// A 5.5-cover viewport; alternating rows begin half a cover earlier.
struct DuoQueueMetrics {
    let side: CGFloat
    let stride: CGFloat
    init(width: CGFloat, gap: CGFloat = 8) {
        side = max(1, (width - 5 * gap) / 5.5)
        stride = side + gap
    }
    func leadingOffset(row: Int) -> CGFloat { row.isMultiple(of: 2) ? 0 : -stride / 2 }
}

struct PlayerPositionedBlur: ViewModifier {
    let position: CGPoint
    let radius: CGFloat
#if DEBUG
    @Environment(\.playerAnimationReferenceEvaluation) private var reference
#endif

    func body(content: Content) -> some View {
#if DEBUG
        if reference {
            content.position(position).blur(radius: radius)
        } else {
            content.blur(radius: radius).position(position)
        }
#else
        // Keep the filter in the glow's local space, before its moving position.
        content.blur(radius: radius).position(position)
#endif
    }
}

struct PlayerVisualRefreshID: Equatable {
    let songID: Int
    let active: Bool
}

private struct PlayerVisualsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var playerVisualsActive: Bool {
        get { self[PlayerVisualsActiveKey.self] }
        set { self[PlayerVisualsActiveKey.self] = newValue }
    }
}

#if DEBUG
private struct PlayerAnimationReferenceEvaluationKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PlayerRenderTestTimeKey: EnvironmentKey {
    static let defaultValue: TimeInterval? = nil
}

extension EnvironmentValues {
    var playerAnimationReferenceEvaluation: Bool {
        get { self[PlayerAnimationReferenceEvaluationKey.self] }
        set { self[PlayerAnimationReferenceEvaluationKey.self] = newValue }
    }

    var playerRenderTestTime: TimeInterval? {
        get { self[PlayerRenderTestTimeKey.self] }
        set { self[PlayerRenderTestTimeKey.self] = newValue }
    }
}
#endif
