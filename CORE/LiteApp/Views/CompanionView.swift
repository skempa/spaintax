import SwiftUI
import RealityKit
import ARKit
import SceneKit

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

    @MainActor
    final class Coordinator {
        weak var arView: ARView?
        var onHDError: (String) -> Void = { _ in }
        private var anchor: AnchorEntity?
        private var creatureEntity: Entity?
        private var adornments: Entity?
        private var currentStage: EvolutionStage = .origin
        private var currentModelFile: String?
        private var wanderTimer: Timer?
        private var orbitTimer: Timer?

        deinit {
            wanderTimer?.invalidate()
            orbitTimer?.invalidate()
        }

        func place(creature: Creature, stage: EvolutionStage) {
            guard let arView else { return }
            let anchor = AnchorEntity(plane: .horizontal, minimumBounds: [0.3, 0.3])
            let entity = makeCreatureEntity(creature: creature, stage: stage)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            self.anchor = anchor
            self.creatureEntity = entity
            currentStage = stage
            currentModelFile = creature.appearance.tripoModelFile
            addAdornments(for: stage, creature: creature)
            startIdle()
            startWander()
        }

        /// After HD generation completes, replace the voxel model with the
        /// Tripo USDZ in place.
        func reloadIfModelChanged(creature: Creature, stage: EvolutionStage) {
            guard creature.appearance.tripoModelFile != currentModelFile,
                  let anchor else { return }
            currentModelFile = creature.appearance.tripoModelFile
            creatureEntity?.removeFromParent()
            adornments = nil
            let entity = makeCreatureEntity(creature: creature, stage: stage)
            anchor.addChild(entity)
            creatureEntity = entity
            addAdornments(for: stage, creature: creature)
        }

        func updateStage(_ stage: EvolutionStage, creature: Creature) {
            guard stage != currentStage else { return }
            currentStage = stage
            addAdornments(for: stage, creature: creature)
            // Evolution grows the creature slightly.
            if let entity = creatureEntity {
                var transform = entity.transform
                transform.scale = SIMD3(repeating: scaleFactor(for: stage))
                entity.move(to: transform, relativeTo: entity.parent, duration: 1.2, timingFunction: .easeInOut)
            }
        }

        private func scaleFactor(for stage: EvolutionStage) -> Float {
            switch stage {
            case .origin:   return 1.0
            case .awakened: return 1.12
            case .ascended: return 1.25
            }
        }

        private func makeCreatureEntity(creature: Creature, stage: EvolutionStage) -> Entity {
            let height: Float = 0.30 * Float(creature.appearance.scale)
            let entity: Entity

            // Tripo-generated USDZ takes priority: a polished, ideally
            // animated model. Falls back to the voxel mesh, but never
            // silently — load failures surface through onHDError.
            var hdEntity: Entity?
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
                        if let animation = loaded.availableAnimations.first {
                            loaded.playAnimation(animation.repeat(), transitionDuration: 0.3)
                        }
                        hdEntity = loaded
                    } catch {
                        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                        let bytes = (attrs?[.size] as? Int) ?? 0
                        onHDError("\(error.localizedDescription) (file: \(bytes / 1024) KB)")
                    }
                }
            }

            if let hdEntity {
                entity = hdEntity
            } else if let image = GameStore.shared.loadImage(named: creature.appearance.processedImageFile),
                      let grid = VoxelExtractor.fromDrawing(image),
                      let voxel = try? VoxelMeshBuilder.entity(for: grid, targetHeight: height) {
                entity = voxel
            } else {
                let fallback = ModelEntity(
                    mesh: .generateBox(size: height * 0.6),
                    materials: [SimpleMaterial(color: .white, isMetallic: false)]
                )
                fallback.position.y = height * 0.3
                entity = fallback
            }
            entity.scale *= SIMD3(repeating: scaleFactor(for: stage))

            let shadowMesh = MeshResource.generatePlane(width: height * 0.9, depth: height * 0.6)
            var shadowMaterial = UnlitMaterial()
            shadowMaterial.color = .init(tint: UIColor.black.withAlphaComponent(0.35))
            let shadow = ModelEntity(mesh: shadowMesh, materials: [shadowMaterial])
            shadow.position = [0, 0.005, 0]
            entity.addChild(shadow)
            return entity
        }

        /// Awakened: orbiting Core motes. Ascended: a second, faster orbit.
        private func addAdornments(for stage: EvolutionStage, creature: Creature) {
            adornments?.removeFromParent()
            adornments = nil
            orbitTimer?.invalidate()
            guard stage >= .awakened, let creatureEntity else { return }

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
            creatureEntity.addChild(holder)
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

        private func startIdle() {
            guard let entity = creatureEntity else { return }
            var up = entity.transform
            up.translation.y += 0.02
            entity.move(to: up, relativeTo: entity.parent, duration: 1.4, timingFunction: .easeInOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let entity = self.creatureEntity else { return }
                var down = entity.transform
                down.translation.y -= 0.02
                entity.move(to: down, relativeTo: entity.parent, duration: 1.4, timingFunction: .easeInOut)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.startIdle()
                }
            }
        }

        private func startWander() {
            wanderTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let entity = self.creatureEntity else { return }
                    var transform = entity.transform
                    transform.translation.x = Float.random(in: -0.2...0.2)
                    transform.translation.z = Float.random(in: -0.2...0.2)
                    entity.move(to: transform, relativeTo: entity.parent, duration: 3.5, timingFunction: .easeInOut)
                }
            }
        }
    }
}
