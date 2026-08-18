import SwiftUI

/// An edge chevron that points toward the creature when it's out of frame,
/// so the player can always find their way back to it.
struct CreaturePointer: View {
    @ObservedObject var pointer: ARPointerState
    let name: String

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if !pointer.isOnScreen, size.width > 0, let placement = placement(in: size) {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 26, weight: .bold))
                        .rotationEffect(.radians(placement.angle))
                    Text(name)
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(10)
                .background(Theme.surfaceRaised, in: Capsule())
                .position(placement.point)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: pointer.isOnScreen)
    }

    /// Where along the screen edge to put the chevron, and its rotation
    /// (0 = pointing up). Uses the projected point when it exists; when the
    /// creature is behind the camera the projection is mirrored, so flip.
    private func placement(in size: CGSize) -> (point: CGPoint, angle: Double)? {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        var target = pointer.screenPoint ?? CGPoint(x: centre.x, y: size.height + 100)
        if pointer.isBehindCamera {
            target = CGPoint(x: 2 * centre.x - target.x, y: 2 * centre.y - target.y)
        }
        let dx = target.x - centre.x
        let dy = target.y - centre.y
        guard dx != 0 || dy != 0 else { return nil }

        // Clamp the direction vector to the screen rectangle (inset).
        let inset: CGFloat = 44
        let halfW = size.width / 2 - inset
        let halfH = size.height / 2 - inset
        let scale = min(halfW / max(abs(dx), 0.001), halfH / max(abs(dy), 0.001))
        let point = CGPoint(x: centre.x + dx * scale, y: centre.y + dy * scale)

        // Chevron points along (dx, dy); atan2 in screen space (y down).
        let angle = atan2(dy, dx) + .pi / 2
        return (point, Double(angle))
    }
}
