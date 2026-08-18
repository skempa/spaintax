import SwiftUI
import RealityKit
import ARKit
import SceneKit
import Combine

/// The home screen IS the companion: your creature standing in your room,
/// with points, streak and focus controls layered over it.
struct CompanionView: View {
    @EnvironmentObject private var app: LiteAppState
    @State private var showFocus = false
    @State private var showSettings = false
    @State private var hdError: String?

    @StateObject private var pointer = ARPointerState()

    private var arAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.isSupported
        #endif
    }

    var body: some View {
        guard let creature = app.creature else { return AnyView(EmptyView()) }

        return AnyView(ZStack {
            if arAvailable {
                ARCompanionView(creature: creature, stage: app.stage,
                                isSpawning: app.isSpawning,
                                pointer: pointer,
                                onHDError: { message in hdError = message })
                .ignoresSafeArea()
            } else {
                // Simulator / no-AR fallback: a quiet 2D home.
                Theme.background
                    .ignoresSafeArea()
                // Without AR, still show the best available version:
                // HD model (interactive 3D) → concept art → drawing sprite.
                if let modelFile = creature.appearance.tripoModelFile,
                   case let url = GameStore.shared.directory.appendingPathComponent(modelFile),
                   FileManager.default.fileExists(atPath: url.path) {
                    HDModelPreview(url: url)
                        .frame(height: 360)
                        .offset(y: 30)
                } else if let conceptFile = creature.appearance.conceptImageFile,
                          let concept = GameStore.shared.loadImage(named: conceptFile) {
                    Image(uiImage: concept)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: (creature.cores.first?.color ?? .cyan).opacity(0.6), radius: 18)
                        .opacity(app.isSpawning ? 0.55 : 1)
                        .offset(y: 40)
                } else {
                    CreatureSpriteView(creature: creature, size: 200)
                        .offset(y: 40)
                }
            }

            VStack {
                statusCard(creature)
                if app.isSpawning || app.spawnFailedMessage != nil {
                    SpawnStatusPill()
                }
                if let hdError {
                    hdErrorBanner(hdError)
                }
                Spacer()
                bottomControls(creature)
            }
            .padding()
        }
        .sheet(isPresented: $showFocus) { FocusSessionView() }
        .sheet(isPresented: $showSettings) { LiteSettingsView() }
        .fullScreenCover(item: $app.celebration) { stage in
            LiteEvolutionView(stage: stage)
        }
        .onAppear { app.refreshDaily() })
    }

    // MARK: - Status

    private func statusCard(_ creature: Creature) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(creature.name)
                        .font(.title2.bold())
                    Text("\(app.stage.displayName) · \(app.lite.growthPoints) Growth Points")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                ConditionBadge(condition: creature.condition)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Theme.textDim)
                }
            }

            // Progress to the next evolution — the single number that matters.
            if let next = app.nextThreshold {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surface)
                            Capsule()
                                .fill(creature.cores.first?.color ?? .cyan)
                                .frame(width: geo.size.width * app.evolutionProgress)
                        }
                    }
                    .frame(height: 10)
                    Text("\(next - app.lite.growthPoints) points to evolution")
                        .font(.caption2)
                        .foregroundStyle(Theme.textFaint)
                }
            } else {
                Text("✨ Fully evolved — keep the streak alive")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 14) {
                statChip("🌅", "+\(app.todayProvisionalPoints) today")
                statChip("🔥", "\(app.lite.streak)-day streak")
                statChip("🧘", "\(app.lite.focusMinutesTotal)m focused")
                Spacer()
            }
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(Theme.text)
    }

    /// HD model failed to display: say why, and offer a way back.
    private func hdErrorBanner(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("HD model couldn't be displayed")
                .font(.footnote.weight(.semibold))
            Text(message)
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Keep blocks") { hdError = nil }
                    .font(.caption.weight(.semibold))
                Button("Retry generation") {
                    app.discardHDModel()
                    hdError = nil
                    app.describeDraft = app.creature?.creatureDescription ?? ""
                    app.screen = .describing
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(Theme.text)
        .padding(.top, 6)
    }

    private func statChip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(symbol).font(.caption)
            Text(text).font(.caption.weight(.medium))
        }
        .foregroundStyle(Theme.textDim)
    }

    // MARK: - Controls

    private func bottomControls(_ creature: Creature) -> some View {
        VStack(spacing: 10) {
            Text(creature.condition.campMessage(name: creature.name, improving: app.isImproving))
                .font(.footnote)
                .foregroundStyle(Theme.text)
                .shadow(radius: 3)
            if creature.appearance.tripoModelFile == nil && !app.isSpawning && app.spawnFailedMessage == nil {
                Button {
                    app.describeDraft = creature.creatureDescription ?? ""
                    app.screen = .describing
                } label: {
                    Text("✨ Bring it to life")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .foregroundStyle(Theme.text)
                }
            }
            Button {
                showFocus = true
            } label: {
                Label("Start a Focus Session", systemImage: "leaf.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(Theme.onAccent)
            }
        }
    }
}

extension EvolutionStage: Identifiable {
    var id: Int { rawValue }
}

/// Interactive 3D preview of the generated USDZ for contexts without AR
/// (simulator, camera denied). SceneKit loads USDZ natively; drag to
/// orbit, pinch to zoom.
struct HDModelPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        if let scene = try? SCNScene(url: url, options: nil) {
            view.scene = scene
            // Gentle turntable so it feels alive even untouched.
            let spin = CABasicAnimation(keyPath: "rotation")
            spin.fromValue = SCNVector4(0, 1, 0, 0)
            spin.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
            spin.duration = 14
            spin.repeatCount = .infinity
            scene.rootNode.addAnimation(spin, forKey: "turntable")
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}


// MARK: - AR layer

/// Publishes where the creature is on screen so the SwiftUI layer can draw
/// an edge pointer when it's out of frame.
@MainActor
final class ARPointerState: ObservableObject {
    /// Projected screen point of the creature (view coordinates), or nil.
    @Published var screenPoint: CGPoint?
    @Published var isOnScreen = true
    @Published var isBehindCamera = false
    var viewSize: CGSize = .zero
}

/// The creature anchored in the player's room — same voxel pipeline as the
/// full game, plus per-stage adornments so evolution is visible in AR.
struct ARCompanionView: UIViewRepresentable {
    let creature: Creature
    let stage: EvolutionStage
    /// True while the Tripo run is in flight — the room shows an egg.
    var isSpawning: Bool = false
    var pointer: ARPointerState
    var onHDError: (String) -> Void = { _ in }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        // Real-world reflections are what made the model read as porcelain.
        config.environmentTexturing = .none
        arView.session.run(config)

        context.coordinator.arView = arView
        context.coordinator.pointer = pointer
        context.coordinator.onHDError = onHDError
        context.coordinator.place(creature: creature, stage: stage, isSpawning: isSpawning)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.pointer.viewSize = uiView.bounds.size
        context.coordinator.updateStage(stage, creature: creature)
        context.coordinator.reloadIfModelChanged(creature: creature, stage: stage, isSpawning: isSpawning)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Entity graph:
    ///   anchor (world)      ← placed 1.2 m in front of the camera immediately,
    ///   └─ creatureRoot        then eased down onto the real floor once found
    ///      ├─ body          ← egg / model; breathe / rock / hop animate this
    ///      ├─ shadow        ← soft contact shadow, stays on the floor
    ///      └─ adornments    ← orbiting Core motes
    @MainActor
    final class Coordinator {
        weak var arView: ARView?
        var pointer = ARPointerState()
        var onHDError: (String) -> Void = { _ in }

        private var anchor: AnchorEntity?
        private var creatureRoot: Entity?
        private var body: Entity?
        private var adornments: Entity?
        private var updateSub: Cancellable?

        private var currentStage: EvolutionStage = .origin
        private var currentModelKey: String = ""
        private var bodyKind: BodyKind = .voxel
        private var hasSkeletalAnimation = false
        private var floorFound = false
        private var hatching = false

        private var behaviourTimer: Timer?
        private var orbitTimer: Timer?
        private var breathGeneration = 0
        private var frameCounter = 0

        private enum BodyKind { case tripo, egg, voxel, fallback }

        /// Extra yaw applied on top of "look at the camera" so the model's
        /// authored front faces the player. Tripo's USDZ forward axis is
        /// unverified: if the creature shows its back, flip this to .pi.
        static let tripoForwardYawOffset: Float = 0
        static let voxelForwardYawOffset: Float = 0

        deinit {
            behaviourTimer?.invalidate()
            orbitTimer?.invalidate()
        }

        // MARK: Placement

        func place(creature: Creature, stage: EvolutionStage, isSpawning: Bool) {
            guard let arView else { return }

            // Appear immediately: a world anchor 1.2 m ahead of the camera at
            // a guessed floor height. No plane scan required to see anything.
            let cam = arView.cameraTransform
            let forward = -normalize(SIMD3(cam.matrix.columns.2.x, 0, cam.matrix.columns.2.z))
            let safeForward = forward.x.isNaN ? SIMD3<Float>(0, 0, -1) : forward
            var origin = cam.translation + safeForward * 1.2
            origin.y = cam.translation.y - 1.3
            let anchor = AnchorEntity(world: origin)
            let root = Entity()
            anchor.addChild(root)
            arView.scene.addAnchor(anchor)
            self.anchor = anchor
            self.creatureRoot = root
            currentStage = stage
            currentModelKey = Self.modelKey(for: creature, spawning: isSpawning)

            installBody(creature: creature, stage: stage, isSpawning: isSpawning)
            addAdornments(for: stage, creature: creature)
            faceCamera(animated: false)
            startBehaviours()

            // Per-frame: settle onto the real floor once ARKit sees it, and
            // keep the pointer state fresh.
            updateSub = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                Task { @MainActor in self?.onFrame() }
            }
        }

        private func onFrame() {
            frameCounter += 1
            if !floorFound, frameCounter % 15 == 0 { tryFindFloor() }
            if frameCounter % 4 == 0 { updatePointer() }
        }

        /// Raycast from screen centre for a horizontal surface; the first hit
        /// re-homes the anchor onto it (height always, position if nearby).
        private func tryFindFloor() {
            guard let arView, let anchor else { return }
            let centre = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let hit = arView.raycast(from: centre, allowing: .estimatedPlane, alignment: .horizontal).first
            else { return }
            let hitPos = SIMD3(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
            var target = anchor.transform
            let current = anchor.position(relativeTo: nil)
            let horizontalDistance = simd_length(SIMD2(hitPos.x - current.x, hitPos.z - current.z))
            target.translation = SIMD3(
                horizontalDistance < 1.0 ? hitPos.x : current.x,
                hitPos.y,
                horizontalDistance < 1.0 ? hitPos.z : current.z
            )
            floorFound = true
            anchor.move(to: target, relativeTo: nil, duration: 0.8, timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                self?.faceCamera(animated: true)
            }
        }

        private func updatePointer() {
            guard let arView, let root = creatureRoot else { return }
            let world = root.position(relativeTo: nil) + SIMD3(0, 0.15, 0)
            let size = arView.bounds.size
            guard size.width > 0 else { return }
            let cam = arView.cameraTransform
            let toCreature = world - cam.translation
            let camForward = -SIMD3(cam.matrix.columns.2.x, cam.matrix.columns.2.y, cam.matrix.columns.2.z)
            let behind = simd_dot(toCreature, camForward) < 0
            if let p = arView.project(world) {
                let margin = size.width * 0.08
                let onScreen = !behind
                    && p.x > margin && p.x < size.width - margin
                    && p.y > margin && p.y < size.height - margin
                pointer.screenPoint = p
                pointer.isBehindCamera = behind
                if pointer.isOnScreen != onScreen { pointer.isOnScreen = onScreen }
            } else {
                pointer.screenPoint = nil
                pointer.isBehindCamera = true
                if pointer.isOnScreen { pointer.isOnScreen = false }
            }
        }

        /// After HD generation completes (or a re-generation lands),
        /// replace the body in place — hatching first if it was an egg.
        func reloadIfModelChanged(creature: Creature, stage: EvolutionStage, isSpawning: Bool) {
            let key = Self.modelKey(for: creature, spawning: isSpawning)
            guard key != currentModelKey, creatureRoot != nil, !hatching else { return }
            currentModelKey = key
            let swap = { [weak self] in
                guard let self else { return }
                self.installBody(creature: creature, stage: stage, isSpawning: isSpawning, bornAnimation: true)
                self.addAdornments(for: stage, creature: creature)
                self.faceCamera(animated: true)
                self.startBehaviours()
            }
            if bodyKind == .egg, creature.appearance.tripoModelFile != nil {
                hatch(then: swap)
            } else {
                swap()
            }
        }

        private static func modelKey(for creature: Creature, spawning: Bool) -> String {
            let base = creature.appearance.tripoModelFile ?? (spawning ? "egg" : "voxel")
            return "\(base)#\(creature.appearance.tripoModelRevision ?? 0)"
        }

        func updateStage(_ stage: EvolutionStage, creature: Creature) {
            guard stage != currentStage else { return }
            currentStage = stage
            addAdornments(for: stage, creature: creature)
            if let body, bodyKind != .egg {
                var transform = body.transform
                transform.scale = SIMD3(repeating: scaleFactor(for: stage))
                body.move(to: transform, relativeTo: body.parent, duration: 1.2, timingFunction: .easeInOut)
            }
        }

        private func scaleFactor(for stage: EvolutionStage) -> Float {
            switch stage {
            case .origin:   return 1.0
            case .awakened: return 1.12
            case .ascended: return 1.25
            }
        }

        // MARK: Body

        private func installBody(creature: Creature, stage: EvolutionStage,
                                 isSpawning: Bool, bornAnimation: Bool = false) {
            guard let root = creatureRoot else { return }
            breathGeneration += 1
            body?.removeFromParent()
            adornments?.removeFromParent(); adornments = nil
            root.children.removeAll()

            let height: Float = 0.30 * Float(creature.appearance.scale)
            let (newBody, kind, animated) = makeBody(creature: creature, height: height, isSpawning: isSpawning)
            bodyKind = kind
            hasSkeletalAnimation = animated
            if kind != .egg { newBody.scale *= SIMD3(repeating: scaleFactor(for: stage)) }
            root.addChild(newBody)
            body = newBody
            root.addChild(makeShadow(height: height, egg: kind == .egg))

            if bornAnimation {
                let target = newBody.transform
                var small = target
                small.scale = target.scale * 0.6
                newBody.transform = small
                newBody.move(to: target, relativeTo: root, duration: 0.6, timingFunction: .easeOut)
            }
            switch kind {
            case .egg:  startRocking()
            case .tripo where hasSkeletalAnimation: break
            default:    startBreathing()
            }
        }

        private func makeBody(creature: Creature, height: Float, isSpawning: Bool) -> (Entity, BodyKind, animated: Bool) {
            if creature.appearance.tripoModelFile == nil, isSpawning {
                return (makeEgg(creature: creature, height: height), .egg, false)
            }

            // Tripo-generated USDZ takes priority. Falls back to the voxel
            // mesh, but never silently — load failures surface via onHDError.
            if let file = creature.appearance.tripoModelFile {
                let url = GameStore.shared.directory.appendingPathComponent(file)
                if !FileManager.default.fileExists(atPath: url.path) {
                    onHDError("Model file is missing (\(file)).")
                } else {
                    do {
                        let loaded = try Entity.load(contentsOf: url)
                        Self.flattenMaterials(in: loaded)
                        let bounds = loaded.visualBounds(relativeTo: nil)
                        let extent = max(bounds.extents.y, 0.001)
                        let factor = height / extent
                        loaded.scale *= SIMD3(repeating: factor)
                        loaded.position.y = -bounds.min.y * factor
                        var animated = false
                        if let animation = loaded.availableAnimations.first {
                            loaded.playAnimation(animation.repeat(), transitionDuration: 0.3)
                            animated = true
                        }
                        let holder = Entity()
                        holder.addChild(loaded)
                        return (holder, .tripo, animated)
                    } catch {
                        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                        let bytes = (attrs?[.size] as? Int) ?? 0
                        onHDError("\(error.localizedDescription) (file: \(bytes / 1024) KB)")
                    }
                }
            }

            if let image = GameStore.shared.loadImage(named: creature.appearance.processedImageFile),
               let grid = VoxelExtractor.fromDrawing(image),
               let voxel = try? VoxelMeshBuilder.entity(for: grid, targetHeight: height) {
                return (voxel, .voxel, false)
            }

            let fallback = ModelEntity(
                mesh: .generateBox(size: height * 0.6),
                materials: [SimpleMaterial(color: .white, isMetallic: false)]
            )
            fallback.position.y = height * 0.3
            return (fallback, .fallback, false)
        }

        /// Tripo ships metallic/roughness maps that read as porcelain in AR.
        /// Force a matte look: full roughness, no metal, no clearcoat.
        private static func flattenMaterials(in entity: Entity) {
            for child in entity.children { flattenMaterials(in: child) }
            guard var model = entity.components[ModelComponent.self] else { return }
            model.materials = model.materials.map { material in
                guard var pbm = material as? PhysicallyBasedMaterial else { return material }
                pbm.roughness = 0.9
                pbm.metallic = 0.0
                pbm.clearcoat = 0.0
                return pbm
            }
            entity.components.set(model)
        }

        /// A soft elliptical contact shadow (radial alpha texture) instead
        /// of the old hard black rectangle.
        private func makeShadow(height: Float, egg: Bool) -> Entity {
            let width = height * (egg ? 0.55 : 0.6)
            let depth = height * (egg ? 0.55 : 0.4)
            var material = UnlitMaterial()
            if let texture = Self.shadowTexture {
                material.color = .init(tint: .black, texture: .init(texture))
                material.blending = .transparent(opacity: .init(floatLiteral: 0.32))
            } else {
                material.color = .init(tint: UIColor.black.withAlphaComponent(0.2))
                material.blending = .transparent(opacity: .init(floatLiteral: 0.2))
            }
            material.opacityThreshold = 0.0
            let shadow = ModelEntity(mesh: .generatePlane(width: width, depth: depth), materials: [material])
            shadow.position = [0, 0.003, 0]
            return shadow
        }

        private static let shadowTexture: TextureResource? = {
            let size = CGSize(width: 128, height: 128)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                let colors = [UIColor.black.withAlphaComponent(1).cgColor,
                              UIColor.black.withAlphaComponent(0.55).cgColor,
                              UIColor.black.withAlphaComponent(0).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1])!
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                                 endCenter: centre, endRadius: size.width / 2, options: [])
            }
            guard let cg = image.cgImage else { return nil }
            return try? TextureResource.generate(from: cg, options: .init(semantic: .color))
        }()

        // MARK: Egg

        private func makeEgg(creature: Creature, height: Float) -> Entity {
            let radius = height * 0.42
            let core = UIColor(creature.cores.first?.color ?? .cyan)
            var shell = PhysicallyBasedMaterial()
            shell.baseColor = .init(tint: core.blended(withFraction: 0.55, of: .white) ?? core)
            shell.roughness = 0.55
            shell.metallic = 0.0
            shell.emissiveColor = .init(color: core.withAlphaComponent(1))
            shell.emissiveIntensity = 0.18

            let egg = ModelEntity(mesh: .generateSphere(radius: radius), materials: [shell])
            egg.scale = [1.0, 1.32, 1.0]
            egg.position.y = radius * 1.32
            egg.name = "eggShell"

            // Speckles: a few flattened dots in a darker shade.
            var speck = PhysicallyBasedMaterial()
            speck.baseColor = .init(tint: core.blended(withFraction: 0.15, of: .black) ?? core)
            speck.roughness = 0.9
            var rng = SystemRandomNumberGenerator()
            for i in 0..<10 {
                let theta = Float(i) / 10 * 2 * .pi + Float.random(in: -0.3...0.3, using: &rng)
                let phi = Float.random(in: 0.35...0.85, using: &rng) * .pi
                let dot = ModelEntity(mesh: .generateSphere(radius: radius * 0.09), materials: [speck])
                dot.position = [sin(phi) * cos(theta) * radius * 0.98,
                                cos(phi) * radius * 0.98,
                                sin(phi) * sin(theta) * radius * 0.98]
                dot.scale = [1, 1, 0.35]
                dot.look(at: .zero, from: dot.position, relativeTo: nil)
                egg.addChild(dot)
            }

            let holder = Entity()
            holder.addChild(egg)
            return holder
        }

        /// Shake, crack, flash — then hand over to the body swap.
        private func hatch(then completion: @escaping () -> Void) {
            guard let egg = body, let root = creatureRoot else { completion(); return }
            hatching = true
            behaviourTimer?.invalidate()
            breathGeneration += 1

            let base = egg.transform
            var tick = 0
            let cracks = makeCracks(on: egg)
            Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] timer in
                Task { @MainActor [weak self] in
                    guard let self else { timer.invalidate(); return }
                    tick += 1
                    let amp = 0.04 + Float(tick) * 0.012
                    var t = base
                    t.rotation = simd_quatf(angle: tick % 2 == 0 ? amp : -amp, axis: [0, 0, 1])
                              * simd_quatf(angle: tick % 3 == 0 ? amp : -amp, axis: [0, 1, 0])
                    egg.move(to: t, relativeTo: egg.parent, duration: 0.12)
                    if tick == 5, cracks.count > 0 { self.reveal(cracks[0]) }
                    if tick == 8, cracks.count > 1 { self.reveal(cracks[1]) }
                    if tick == 11, cracks.count > 2 { self.reveal(cracks[2]) }
                    if tick >= 13 {
                        timer.invalidate()
                        self.flash(in: root) { [weak self] in
                            self?.hatching = false
                            completion()
                        }
                    }
                }
            }
        }

        private func makeCracks(on egg: Entity) -> [ModelEntity] {
            guard let shell = egg.children.first(where: { $0.name == "eggShell" }) as? ModelEntity else { return [] }
            let radius = (shell.model?.mesh.bounds.extents.x ?? 0.1) / 2
            var material = UnlitMaterial(color: UIColor(white: 0.12, alpha: 1))
            material.blending = .opaque
            var cracks: [ModelEntity] = []
            for (i, angle) in [Float(0.4), Float(2.2), Float(4.1)].enumerated() {
                let crack = ModelEntity(mesh: .generateBox(size: [radius * 0.06, radius * 0.9, radius * 0.06]),
                                        materials: [material])
                crack.position = [cos(angle) * radius * 0.98, radius * (0.1 + Float(i) * 0.15), sin(angle) * radius * 0.98]
                crack.orientation = simd_quatf(angle: angle + .pi / 2, axis: [0, 1, 0])
                    * simd_quatf(angle: Float(i) * 0.5 - 0.5, axis: [0, 0, 1])
                crack.scale = .init(repeating: 0.001)
                shell.addChild(crack)
                cracks.append(crack)
            }
            return cracks
        }

        private func reveal(_ crack: ModelEntity) {
            var t = crack.transform
            t.scale = .one
            crack.move(to: t, relativeTo: crack.parent, duration: 0.1, timingFunction: .easeOut)
        }

        private func flash(in root: Entity, completion: @escaping () -> Void) {
            var material = UnlitMaterial(color: .white)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.92))
            let flash = ModelEntity(mesh: .generateSphere(radius: 0.18), materials: [material])
            flash.position.y = 0.16
            flash.scale = .init(repeating: 0.05)
            root.addChild(flash)
            var big = flash.transform
            big.scale = .init(repeating: 1.6)
            flash.move(to: big, relativeTo: root, duration: 0.18, timingFunction: .easeOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                var gone = flash.transform
                gone.scale = .init(repeating: 0.001)
                flash.move(to: gone, relativeTo: root, duration: 0.24, timingFunction: .easeIn)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                    flash.removeFromParent()
                    completion()
                }
            }
        }

        // MARK: Facing the player

        private var forwardYawOffset: Float {
            switch bodyKind {
            case .tripo: return Self.tripoForwardYawOffset
            case .voxel: return Self.voxelForwardYawOffset
            case .egg, .fallback: return 0
            }
        }

        /// Yaw the root (world space) so the model's front points at the
        /// camera. Rotating +Z about Y by θ gives (sin θ, 0, cos θ), so the
        /// yaw that points +Z at the camera is atan2(dx, dz).
        private func faceCamera(animated: Bool) {
            guard let arView, let root = creatureRoot else { return }
            let cam = arView.cameraTransform.translation
            let pos = root.position(relativeTo: nil)
            let dx = cam.x - pos.x, dz = cam.z - pos.z
            guard dx * dx + dz * dz > 1e-6 else { return }
            let yaw = atan2(dx, dz) + forwardYawOffset
            let q = simd_quatf(angle: yaw, axis: [0, 1, 0])
            if animated {
                let target = Transform(scale: root.scale(relativeTo: nil), rotation: q, translation: pos)
                root.move(to: target, relativeTo: nil, duration: 0.6, timingFunction: .easeInOut)
            } else {
                root.setOrientation(q, relativeTo: nil)
            }
        }

        // MARK: Procedural motion

        /// Subtle breathing when the model has no skeletal animation. Each
        /// chain carries the generation it started with and stops when a
        /// body swap bumps it — no doubled loops.
        private func startBreathing() {
            breathGeneration += 1
            breathe(inhale: true, generation: breathGeneration)
        }

        private func breathe(inhale: Bool, generation: Int) {
            guard generation == breathGeneration, let body, bodyKind != .egg else { return }
            var t = body.transform
            let base = scaleFactor(for: currentStage)
            t.scale = SIMD3(base, base * (inhale ? 1.03 : 1.0), base)
            t.translation.y = inhale ? 0.008 : 0
            body.move(to: t, relativeTo: body.parent, duration: 2.4, timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.45) { [weak self] in
                self?.breathe(inhale: !inhale, generation: generation)
            }
        }

        /// The egg rocks gently — something is alive in there.
        private func startRocking() {
            breathGeneration += 1
            rock(left: true, generation: breathGeneration)
        }

        private func rock(left: Bool, generation: Int) {
            guard generation == breathGeneration, let body, bodyKind == .egg else { return }
            var t = body.transform
            t.rotation = simd_quatf(angle: left ? 0.035 : -0.035, axis: [0, 0, 1])
            body.move(to: t, relativeTo: body.parent, duration: 1.6, timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) { [weak self] in
                self?.rock(left: !left, generation: generation)
            }
        }

        /// One scheduler picks a small behaviour every 6–12 s: a hop, a
        /// look-around, or a short wander. The egg only wanders.
        private func startBehaviours() {
            behaviourTimer?.invalidate()
            scheduleNextBehaviour()
        }

        private func scheduleNextBehaviour() {
            let delay = TimeInterval.random(in: 6...12)
            behaviourTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.hatching else { return }
                    switch Int.random(in: 0..<3) {
                    case 0:  self.hop()
                    case 1:  self.lookAround()
                    default: self.wander()
                    }
                    self.scheduleNextBehaviour()
                }
            }
        }

        private func hop() {
            guard let body, !hasSkeletalAnimation, bodyKind != .egg else { wander(); return }
            var up = body.transform
            up.translation.y += 0.06
            body.move(to: up, relativeTo: body.parent, duration: 0.22, timingFunction: .easeOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { [weak self] in
                guard let body = self?.body else { return }
                var down = body.transform
                down.translation.y = 0
                body.move(to: down, relativeTo: body.parent, duration: 0.25, timingFunction: .easeIn)
            }
        }

        private func lookAround() {
            guard let root = creatureRoot, bodyKind != .egg else { wander(); return }
            let side: Float = Bool.random() ? 1 : -1
            var t = root.transform
            t.rotation = t.rotation * simd_quatf(angle: side * 0.4, axis: [0, 1, 0])
            root.move(to: t, relativeTo: root.parent, duration: 0.8, timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.faceCamera(animated: true)
            }
        }

        private func wander() {
            guard let root = creatureRoot else { return }
            var t = root.transform
            t.translation.x = Float.random(in: -0.2...0.2)
            t.translation.z = Float.random(in: -0.2...0.2)
            root.move(to: t, relativeTo: root.parent, duration: 3.0, timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) { [weak self] in
                self?.faceCamera(animated: true)
            }
        }

        // MARK: Adornments

        /// Awakened: orbiting Core motes. Ascended: a second, faster orbit.
        private func addAdornments(for stage: EvolutionStage, creature: Creature) {
            adornments?.removeFromParent()
            adornments = nil
            orbitTimer?.invalidate()
            guard stage >= .awakened, bodyKind != .egg, let root = creatureRoot else { return }

            let holder = Entity()
            let rings = stage == .ascended ? 2 : 1
            for ring in 0..<rings {
                let orbit = Entity()
                orbit.name = "orbit\(ring)"
                let motes = 3 + ring * 2
                let radius: Float = 0.14 + Float(ring) * 0.05
                let color = UIColor(creature.cores.first?.color ?? .cyan)
                for i in 0..<motes {
                    let mote = ModelEntity(
                        mesh: .generateSphere(radius: 0.008),
                        materials: [UnlitMaterial(color: color.withAlphaComponent(0.9))]
                    )
                    let angle = Float(i) / Float(motes) * 2 * .pi
                    mote.position = [cos(angle) * radius, 0.16 + Float(ring) * 0.06, sin(angle) * radius]
                    orbit.addChild(mote)
                }
                holder.addChild(orbit)
            }
            root.addChild(holder)
            adornments = holder

            orbitTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let holder = self?.adornments else { return }
                    for (index, orbit) in holder.children.enumerated() {
                        let direction: Float = index % 2 == 0 ? 1 : -1
                        orbit.transform.rotation *= simd_quatf(angle: direction * 0.02, axis: [0, 1, 0])
                    }
                }
            }
        }
    }
}

private extension UIColor {
    func blended(withFraction fraction: CGFloat, of other: UIColor) -> UIColor? {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return nil }
        return UIColor(red: r1 + (r2 - r1) * fraction, green: g1 + (g2 - g1) * fraction,
                       blue: b1 + (b2 - b1) * fraction, alpha: 1)
    }
}
