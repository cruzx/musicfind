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
