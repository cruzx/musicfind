import SwiftUI

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
