import SwiftUI
import RealityKit
import ARKit

/// Places the creature into the player's physical environment.
///
/// "My creature is in my world": the creature stands on detected floor
/// planes, idles with a bobbing animation, wanders short distances, and
/// enemies materialise as Core-coloured rifts nearby during combat.
/// No GPS — the experience is anchored to the room, not the world.
struct ARAdventureView: UIViewRepresentable {
    @ObservedObject var engine: AdventureEngine

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)

        // Coaching overlay guides the player to scan the floor.
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .horizontalPlane
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coaching)

        context.coordinator.arView = arView
        context.coordinator.placeCreatureWhenReady()
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.sync(with: engine)
    }

    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }

    @MainActor
    final class Coordinator {
        let engine: AdventureEngine
        weak var arView: ARView?
        private var creatureAnchor: AnchorEntity?
        private var creatureEntity: ModelEntity?
        private var enemyEntity: ModelEntity?
        private var wanderTimer: Timer?
        private var inCombat = false

        init(engine: AdventureEngine) {
            self.engine = engine
        }

        deinit {
            wanderTimer?.invalidate()
        }

        /// Anchors the creature to the first detected horizontal plane.
        func placeCreatureWhenReady() {
            guard let arView else { return }

            let anchor = AnchorEntity(plane: .horizontal, minimumBounds: [0.3, 0.3])
            let creature = makeCreatureEntity()
            anchor.addChild(creature)
            arView.scene.addAnchor(anchor)

            creatureAnchor = anchor
            creatureEntity = creature

            startIdleAnimation()
            startWandering()
        }

        /// The creature is a billboarded plane textured with the player's
        /// processed drawing, floating just above the floor with a soft
        /// shadow disc — readable from any angle and faithful to what
        /// they drew.
        private func makeCreatureEntity() -> ModelEntity {
            let scale = Float(engine.creature.appearance.scale)
            let height: Float = 0.28 * scale

            var material = UnlitMaterial()
            if let image = GameStore.shared.loadImage(named: engine.creature.appearance.processedImageFile),
               let cgImage = image.cgImage,
               let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color)) {
                material.color = .init(texture: .init(texture))
                material.blending = .transparent(opacity: 1.0)
            } else {
                material.color = .init(tint: .white)
            }

            let mesh = MeshResource.generatePlane(width: height, height: height)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = [0, height / 2 + 0.02, 0]

            // Shadow disc grounds the creature visually.
            let shadowMesh = MeshResource.generatePlane(width: height * 0.8, depth: height * 0.5)
            var shadowMaterial = UnlitMaterial()
            shadowMaterial.color = .init(tint: UIColor.black.withAlphaComponent(0.35))
            let shadow = ModelEntity(mesh: shadowMesh, materials: [shadowMaterial])
            shadow.position = [0, -height / 2, 0]
            entity.addChild(shadow)

            // Billboard toward the camera on iOS 18+; on earlier targets
            // the sprite simply faces its spawn orientation.
            if #available(iOS 18.0, *) {
                entity.components.set(BillboardComponent())
            }

            return entity
        }

        private func startIdleAnimation() {
            guard let entity = creatureEntity else { return }
            var transform = entity.transform
            transform.translation.y += 0.03
            entity.move(to: transform, relativeTo: entity.parent, duration: 1.4, timingFunction: .easeInOut)
            // Loop the bob.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let entity = self.creatureEntity else { return }
                var down = entity.transform
                down.translation.y -= 0.03
                entity.move(to: down, relativeTo: entity.parent, duration: 1.4, timingFunction: .easeInOut)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.startIdleAnimation()
                }
            }
        }

        /// Short random walks around the anchor while exploring.
        private func startWandering() {
            wanderTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.inCombat, let entity = self.creatureEntity else { return }
                    var transform = entity.transform
                    transform.translation.x = Float.random(in: -0.25...0.25)
                    transform.translation.z = Float.random(in: -0.25...0.25)
                    entity.move(to: transform, relativeTo: entity.parent, duration: 3, timingFunction: .easeInOut)
                }
            }
        }

        /// Mirrors engine phase into the AR scene (enemy rift in/out).
        func sync(with engine: AdventureEngine) {
            switch engine.phase {
            case .combat(let enemy):
                inCombat = true
                if enemyEntity == nil { spawnEnemy(enemy) }
            default:
                inCombat = false
                if enemyEntity != nil { removeEnemy() }
            }
        }

        /// Enemies appear as glowing rifts beside the creature.
        private func spawnEnemy(_ enemy: Enemy) {
            guard let anchor = creatureAnchor else { return }
            let size: Float = enemy.isBoss ? 0.22 : 0.12
            let mesh = MeshResource.generateSphere(radius: size)
            var material = UnlitMaterial()
            material.color = .init(tint: enemy.isBoss
                ? UIColor.purple.withAlphaComponent(0.9)
                : UIColor.red.withAlphaComponent(0.85))
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = [0.35, size + 0.02, -0.1]
            anchor.addChild(entity)
            enemyEntity = entity

            // Menacing pulse.
            var pulse = entity.transform
            pulse.scale = SIMD3(repeating: 1.15)
            entity.move(to: pulse, relativeTo: anchor, duration: 0.6, timingFunction: .easeInOut)
        }

        private func removeEnemy() {
            enemyEntity?.removeFromParent()
            enemyEntity = nil
        }
    }
}
