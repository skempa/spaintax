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
    @State private var showEnhance = false
    @State private var hdError: String?

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
                ARCompanionView(creature: creature, stage: app.stage, onHDError: { message in
                    hdError = message
                })
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
                        .offset(y: 40)
                } else {
                    CreatureSpriteView(creature: creature, size: 200)
                        .offset(y: 40)
                }
            }

            VStack {
                statusCard(creature)
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
        .sheet(isPresented: $showEnhance) { EnhanceSheet() }
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
            if creature.appearance.tripoModelFile == nil {
                Button {
                    showEnhance = true
                } label: {
                    Text("✨ Bring to life in HD")
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

/// The creature anchored to the player's floor — same voxel pipeline as
/// the full game, plus per-stage adornments so evolution is visible in AR.
struct ARCompanionView: UIViewRepresentable {
    let creature: Creature
    let stage: EvolutionStage
    var onHDError: (String) -> Void = { _ in }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)

        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .horizontalPlane
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coaching)

        context.coordinator.arView = arView
        context.coordinator.onHDError = onHDError
        context.coordinator.place(creature: creature, stage: stage)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.updateStage(stage, creature: creature)
        context.coordinator.reloadIfModelChanged(creature: creature, stage: stage)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Entity graph:
    ///   anchor
    ///   └─ creatureRoot   ← world yaw (faces the camera) + wander position
    ///      ├─ body        ← the model; breathe / bob / hop animate this
    ///      ├─ shadow      ← stays flat on the floor, doesn't bob
    ///      └─ adornments  ← orbiting Core motes
    @MainActor
    final class Coordinator {
        weak var arView: ARView?
        var onHDError: (String) -> Void = { _ in }

        private var anchor: AnchorEntity?
        private var creatureRoot: Entity?
        private var body: Entity?
        private var adornments: Entity?
        private var anchoredSub: Cancellable?

        private var currentStage: EvolutionStage = .origin
        private var currentModelKey: String = ""
        private var bodyKind: BodyKind = .voxel
        private var hasSkeletalAnimation = false

        private var behaviourTimer: Timer?
        private var orbitTimer: Timer?
        private var breathing = false

        private enum BodyKind { case tripo, voxel, fallback }

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

        func place(creature: Creature, stage: EvolutionStage) {
            guard let arView else { return }
            let anchor = AnchorEntity(plane: .horizontal, minimumBounds: [0.3, 0.3])
            let root = Entity()
            anchor.addChild(root)
            arView.scene.addAnchor(anchor)
            self.anchor = anchor
            self.creatureRoot = root
            currentStage = stage
            currentModelKey = Self.modelKey(for: creature)

            installBody(creature: creature, stage: stage)
            addAdornments(for: stage, creature: creature)

            // The plane anchor's world transform is identity until ARKit
            // finds a floor — face the camera the moment it does.
            anchoredSub = arView.scene.subscribe(to: SceneEvents.AnchoredStateChanged.self, on: anchor) { [weak self] event in
                guard event.isAnchored else { return }
                Task { @MainActor in self?.faceCamera(animated: false) }
            }
            startBehaviours()
        }

        /// After HD generation completes (or a re-generation lands),
        /// replace the body in place with a small "born" scale-in.
        func reloadIfModelChanged(creature: Creature, stage: EvolutionStage) {
            let key = Self.modelKey(for: creature)
            guard key != currentModelKey, creatureRoot != nil else { return }
            currentModelKey = key
            installBody(creature: creature, stage: stage, bornAnimation: true)
            addAdornments(for: stage, creature: creature)
            faceCamera(animated: true)
        }

        private static func modelKey(for creature: Creature) -> String {
            "\(creature.appearance.tripoModelFile ?? "voxel")#\(creature.appearance.tripoModelRevision ?? 0)"
        }

        func updateStage(_ stage: EvolutionStage, creature: Creature) {
            guard stage != currentStage else { return }
            currentStage = stage
            addAdornments(for: stage, creature: creature)
            // Evolution grows the creature slightly.
            if let body {
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

        private func installBody(creature: Creature, stage: EvolutionStage, bornAnimation: Bool = false) {
            guard let root = creatureRoot else { return }
            body?.removeFromParent()
            adornments?.removeFromParent(); adornments = nil
            root.children.removeAll()

            let height: Float = 0.30 * Float(creature.appearance.scale)
            let (newBody, kind, animated) = makeBody(creature: creature, height: height)
            bodyKind = kind
            hasSkeletalAnimation = animated
            newBody.scale *= SIMD3(repeating: scaleFactor(for: stage))
            root.addChild(newBody)
            body = newBody

            let shadowMesh = MeshResource.generatePlane(width: height * 0.9, depth: height * 0.6)
            var shadowMaterial = UnlitMaterial()
            shadowMaterial.color = .init(tint: UIColor.black.withAlphaComponent(0.35))
            let shadow = ModelEntity(mesh: shadowMesh, materials: [shadowMaterial])
            shadow.position = [0, 0.005, 0]
            root.addChild(shadow)

            if bornAnimation {
                let target = newBody.transform
                var small = target
                small.scale = target.scale * 0.6
                newBody.transform = small
                newBody.move(to: target, relativeTo: root, duration: 0.6, timingFunction: .easeOut)
            }
            breathing = false
            if !hasSkeletalAnimation { startBreathing() }
        }

        /// Tripo-generated USDZ takes priority: a polished, ideally animated
        /// model. Falls back to the voxel mesh, but never silently — load
        /// failures surface through onHDError.
        private func makeBody(creature: Creature, height: Float) -> (Entity, BodyKind, animated: Bool) {
            if let file = creature.appearance.tripoModelFile {
                let url = GameStore.shared.directory.appendingPathComponent(file)
                if !FileManager.default.fileExists(atPath: url.path) {
                    onHDError("Model file is missing (\(file)).")
                } else {
                    do {
                        let loaded = try Entity.load(contentsOf: url)
                        // Normalise to the target height, feet on the floor.
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
                        // Wrap so the body's own transform stays clean for bob/breathe.
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

        // MARK: Facing the player

        private var forwardYawOffset: Float {
            switch bodyKind {
            case .tripo:    return Self.tripoForwardYawOffset
            case .voxel:    return Self.voxelForwardYawOffset
            case .fallback: return 0
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
                let target = Transform(
                    scale: root.scale(relativeTo: nil),
                    rotation: q,
                    translation: pos
                )
                root.move(to: target, relativeTo: nil, duration: 0.6, timingFunction: .easeInOut)
            } else {
                root.setOrientation(q, relativeTo: nil)
            }
        }

        // MARK: Procedural motion

        /// Subtle breathing when the model has no skeletal animation.
        private func startBreathing() {
            guard !breathing else { return }
            breathing = true
            breathe(inhale: true)
        }

        private func breathe(inhale: Bool) {
            guard breathing, let body else { return }
            var t = body.transform
            let base = scaleFactor(for: currentStage)
            t.scale = SIMD3(base, base * (inhale ? 1.03 : 1.0), base)
            t.translation.y = inhale ? 0.008 : 0
            body.move(to: t, relativeTo: body.parent, duration: 2.4, timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.45) { [weak self] in
                self?.breathe(inhale: !inhale)
            }
        }

        /// One scheduler picks a small behaviour every 6–12 s: a hop, a
        /// look-around, or a short wander. Replaces the old fixed wander timer.
        private func startBehaviours() {
            behaviourTimer?.invalidate()
            scheduleNextBehaviour()
        }

        private func scheduleNextBehaviour() {
            let delay = TimeInterval.random(in: 6...12)
            behaviourTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
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
            guard let body, !hasSkeletalAnimation else { wander(); return }
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
            guard let root = creatureRoot else { return }
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
            guard stage >= .awakened, let root = creatureRoot else { return }

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

            // Slow orbital spin, opposite directions per ring.
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
