import Foundation
import UIKit

/// Orchestrates the full Tripo pipeline for one creature:
///
///   drawing → concept art (image-to-image, pose-canonicalised)
///           → 3D model (image-to-model)
///           → rig + preset animations (best-effort)
///           → USDZ export → downloaded into the GameStore
///
/// Every stage that fails after the model exists degrades gracefully:
/// animated → static model → (if modelling itself fails) the voxel
/// creature stays. Costs credits on the user's Tripo account.
@MainActor
final class TripoCreatureEnhancer: ObservableObject {

    enum Stage: Equatable {
        case idle
        case uploading
        case conceptArt
        case modeling
        case rigging
        case animating
        case exporting
        case done
        case failed(String)

        var label: String {
            switch self {
            case .idle:       return "Ready"
            case .uploading:  return "Uploading your drawing…"
            case .conceptArt: return "Interpreting the drawing…"
            case .modeling:   return "Sculpting it in 3D…"
            case .rigging:    return "Building its skeleton…"
            case .animating:  return "Teaching it to move…"
            case .exporting:  return "Bringing it home…"
            case .done:       return "Alive!"
            case .failed(let message): return message
            }
        }
    }

    struct Result {
        var conceptImageFile: String?
        var modelFile: String?
        var animated: Bool
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var conceptImage: UIImage?
    /// Non-fatal stage skips (concept art, animation) — surfaced in the
    /// UI so failures are diagnosable instead of silent.
    @Published private(set) var notes: [String] = []

    /// The API requires an explicit model version even though the SDK
    /// marks it optional. Allowed (Aug 2026): P1-20260311, v2.5-20250123,
    /// v3.0-20250812, v3.1-20260211.
    static let modelVersion = "v3.1-20260211"

    /// Bumped with every pipeline change; shown in the UI so stale-build
    /// confusion is impossible.
    static let pipelineRevision = "r4"

    /// The pose-canonicalising interpretation prompt — Tripo's own
    /// rigging guidance baked in: limbs separated, T-pose.
    static let conceptPrompt = """
    cute stylized 3D game creature, faithful to this child-like drawing, \
    keep its exact colors, proportions and distinctive features, \
    standing upright in T-pose, arms spread away from the body, \
    legs slightly apart, limbs clearly separated from the torso, \
    full body, plain background
    """

    private var runTask: Task<Void, Never>?

    func cancel() {
        runTask?.cancel()
        runTask = nil
        if stage != .done { stage = .idle }
    }

    /// Runs the pipeline; calls `completion` on success with files saved
    /// into the GameStore directory.
    func run(apiKey: String, completion: @escaping (Result) -> Void) {
        guard stage == .idle || stage.isFailure else { return }
        let client = TripoClient(apiKey: apiKey)

        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.pipeline(client: client)
                self.stage = .done
                completion(result)
            } catch is CancellationError {
                self.stage = .idle
            } catch {
                // Tag the failure with the stage it died in.
                self.stage = .failed("Failed during '\(self.stage.label)' — \(error.localizedDescription)")
            }
        }
    }

    private func pipeline(client: TripoClient) async throws -> Result {
        let store = GameStore.shared

        // 1. Upload the original drawing.
        stage = .uploading
        guard let drawing = store.loadImage(named: "creature-original.png"),
              let png = drawing.pngData() else {
            throw TripoClient.TripoError.badResponse
        }
        let drawingToken = try await client.uploadFile(png, filename: "drawing.png")

        // 2. Concept art: the AI's interpretation, in a rig-friendly pose.
        stage = .conceptArt
        var conceptFile: String?
        var modelInput: [String: Any] = ["file_token": drawingToken]
        do {
            let conceptTaskID = try await client.createTask("generation/image-to-image", body: [
                "file": ["file_token": drawingToken],
                "prompt": Self.conceptPrompt,
            ])
            let conceptTask = try await client.waitForTask(conceptTaskID, timeout: 300)
            if let imageURL = conceptTask.output?.primaryImageURL {
                let imageData = try await client.download(imageURL)
                if let image = UIImage(data: imageData) {
                    conceptImage = image
                    store.saveImage(image, named: "creature-concept.png")
                    conceptFile = "creature-concept.png"
                }
                modelInput = ["url": imageURL]
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Concept stage is an enhancer, not a gate: fall back to the
            // raw drawing as the 3D input.
            notes.append("Concept art skipped: \(error.localizedDescription)")
        }

        // 3. The 3D model itself.
        stage = .modeling
        let modelTaskID = try await client.createTask("generation/image-to-model", body: [
            "file": modelInput,
            "model": Self.modelVersion,
            "texture": true,
            "pbr": true,
        ])
        let modelTask = try await client.waitForTask(modelTaskID, timeout: 900)
        var exportInput = modelTaskID
        var animated = false

        // 4. Rig + animations — best effort, never fatal.
        do {
            stage = .rigging
            let checkID = try await client.createTask("animations/rig-check", body: ["input": modelTaskID])
            let check = try await client.waitForTask(checkID, timeout: 300)
            if check.output?.riggable != false {
                let rigType = check.output?.recommendedRigType ?? check.output?.rigType ?? "quadruped"
                let rigID = try await client.createTask("animations/rig", body: [
                    "input": modelTaskID,
                    "rig_type": rigType,
                    "spec": "tripo",
                ])
                _ = try await client.waitForTask(rigID, timeout: 600)

                stage = .animating
                let walkPreset = rigType == "biped" ? "preset:walk" : "preset:\(rigType):walk"
                let retargetID = try await client.createTask("animations/retarget", body: [
                    "input": rigID,
                    "animations": ["preset:idle", walkPreset],
                    "export_with_geometry": true,
                ])
                _ = try await client.waitForTask(retargetID, timeout: 600)
                exportInput = retargetID
                animated = true
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Static model still ships.
            notes.append("Animation skipped: \(error.localizedDescription)")
            exportInput = modelTaskID
            animated = false
        }

        // 5. Export as USDZ (RealityKit's native format) and download.
        stage = .exporting
        let convertID = try await client.createTask("models/convert", body: [
            "input": exportInput,
            "format": "USDZ",
            "with_animation": animated,
        ])
        let converted = try await client.waitForTask(convertID, timeout: 600)
        guard let modelURL = converted.output?.primaryModelURL else {
            // Conversion produced nothing usable — try the raw model URL.
            if let raw = modelTask.output?.primaryModelURL, raw.lowercased().contains("usdz") {
                let data = try await client.download(raw)
                try data.write(to: GameStore.shared.directory.appendingPathComponent("creature-tripo.usdz"), options: .atomic)
                return Result(conceptImageFile: conceptFile, modelFile: "creature-tripo.usdz", animated: false)
            }
            throw TripoClient.TripoError.badResponse
        }
        let modelData = try await client.download(modelURL)
        // Sanity check: a USDZ is a zip and must start with "PK".
        guard modelData.count > 4, modelData[0] == 0x50, modelData[1] == 0x4B else {
            notes.append("Downloaded model wasn't a valid USDZ (\(modelData.count) bytes) — URL may have expired.")
            throw TripoClient.TripoError.badResponse
        }
        try modelData.write(to: GameStore.shared.directory.appendingPathComponent("creature-tripo.usdz"), options: .atomic)

        return Result(conceptImageFile: conceptFile, modelFile: "creature-tripo.usdz", animated: animated)
    }
}

private extension TripoCreatureEnhancer.Stage {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
