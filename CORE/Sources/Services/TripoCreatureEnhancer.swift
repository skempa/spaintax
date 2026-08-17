import Foundation
import UIKit

/// Orchestrates the full Tripo pipeline for one creature:
///
///   drawing → concept art (image-to-image, pose-canonicalised)
///           → 3D model (image-to-model)
///           → rig + preset animations (best-effort)
///           → USDZ export → downloaded into the GameStore
///
/// The run is **resumable**: every Tripo task ID is written into a
/// `SpawnRecord` (persisted by the owner) the moment the task is created,
/// so a suspended or killed app can pick the run back up mid-flight
/// instead of losing it. Tripo keeps working server-side regardless.
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

        /// Technical label (settings/debug).
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

        /// The player-facing line — one sentence, never a checklist.
        var narrative: String {
            switch self {
            case .idle:       return "Getting ready…"
            case .uploading:  return "Reading your lines…"
            case .conceptArt: return "Imagining what it looks like…"
            case .modeling:   return "Giving it a body…"
            case .rigging:    return "Growing bones…"
            case .animating:  return "Teaching it to move…"
            case .exporting:  return "Opening the door to your room…"
            case .done:       return "It's here."
            case .failed(let message): return message
            }
        }

        var isRunning: Bool {
            switch self {
            case .idle, .done, .failed: return false
            default: return true
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

    var isRunning: Bool { stage.isRunning }

    /// The API requires an explicit model version even though the SDK
    /// marks it optional. Allowed (Aug 2026): P1-20260311, v2.5-20250123,
    /// v3.0-20250812, v3.1-20260211.
    static let modelVersion = "v3.1-20260211"

    /// Rig/retarget use their own model line; the server default is a
    /// de-listed version, so it must be sent explicitly.
    /// Allowed (Aug 2026): v1.0-20240301, v2.5-20260210.
    static let rigModelVersion = "v2.5-20260210"

    /// Bumped with every pipeline change; shown in the UI so stale-build
    /// confusion is impossible.
    static let pipelineRevision = "r8"

    static let conceptFileName = "creature-concept.png"
    static let modelFileName = "creature-tripo.usdz"

    // MARK: Prompt

    /// The locked foundation: every creature comes out in this one style
    /// regardless of what was drawn. The player's description only says
    /// *what* the creature is; this says *how* it is rendered.
    static let styleBlock = """
    soft, rounded, stylized 3D collectible creature, \
    matte hand-painted textures with a gentle rim light, \
    friendly proportions with a slightly oversized head and expressive eyes, \
    clean readable silhouette, cohesive palette drawn from the sketch, \
    single character, plain neutral background, polished game asset
    """
    /// Always last — Tripo's own auto-rig guidance: T-pose, limbs separated.
    static let poseBlock = """
    standing upright in T-pose, arms spread away from the body, \
    legs slightly apart, limbs clearly separated from the torso, \
    full body, plain background
    """

    static func prompt(description: String?) -> String {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subject = trimmed.isEmpty ? nil : "Creature: \(trimmed)."
        return ([subject, styleBlock, poseBlock].compactMap { $0 }).joined(separator: ", ")
    }

    // MARK: Run / resume

    private var runTask: Task<Void, Never>?
    private var persist: ((SpawnRecord) -> Void)?

    func cancel() {
        runTask?.cancel()
        runTask = nil
        if stage != .done { stage = .idle }
    }

    /// Starts a fresh run.
    func run(apiKey: String,
             description: String?,
             persist: @escaping (SpawnRecord) -> Void,
             completion: @escaping (Result) -> Void) {
        let record = SpawnRecord(startedAt: Date(), description: description)
        start(record: record, apiKey: apiKey, persist: persist, completion: completion)
    }

    /// Continues a persisted run from whichever stage it reached.
    func resume(record: SpawnRecord,
                apiKey: String,
                persist: @escaping (SpawnRecord) -> Void,
                completion: @escaping (Result) -> Void) {
        start(record: record, apiKey: apiKey, persist: persist, completion: completion)
    }

    private func start(record: SpawnRecord,
                       apiKey: String,
                       persist: @escaping (SpawnRecord) -> Void,
                       completion: @escaping (Result) -> Void) {
        guard !isRunning else { return }
        self.persist = persist
        notes = record.notes
        stage = Self.initialStage(for: record)
        if let file = record.conceptFile, conceptImage == nil {
            conceptImage = GameStore.shared.loadImage(named: file)
        }
        let client = TripoClient(apiKey: apiKey)

        runTask = Task { [weak self] in
            guard let self else { return }
            var record = record
            record.failedMessage = nil
            do {
                let result = try await self.pipeline(client: client, record: &record)
                self.stage = .done
                completion(result)
            } catch is CancellationError {
                self.stage = .idle
            } catch {
                let message = "Failed during '\(self.stage.label)' — \(error.localizedDescription)"
                record.failedMessage = message
                self.persist?(record)
                self.stage = .failed(message)
            }
        }
    }

    /// Where a resumed record should report itself while the first poll
    /// is in flight — the UI shows the right line immediately.
    private static func initialStage(for r: SpawnRecord) -> Stage {
        if r.convertTaskID != nil { return .exporting }
        if r.retargetTaskID != nil { return .animating }
        if r.rigTaskID != nil || r.rigCheckTaskID != nil { return .rigging }
        if r.modelTaskID != nil { return .modeling }
        if r.conceptTaskID != nil { return .conceptArt }
        return .uploading
    }

    // MARK: Pipeline

    private func save(_ record: SpawnRecord) {
        var r = record
        r.notes = notes
        persist?(r)
    }

    private func note(_ text: String, _ record: inout SpawnRecord) {
        notes.append(text)
        record.notes = notes
        save(record)
    }

    private func pipeline(client: TripoClient, record: inout SpawnRecord) async throws -> Result {
        let store = GameStore.shared

        // 1. Upload the original drawing (idempotent: reuse the token).
        stage = .uploading
        if record.drawingToken == nil {
            guard let drawing = store.loadImage(named: "creature-original.png"),
                  let png = drawing.pngData() else {
                throw TripoClient.TripoError.badResponse
            }
            record.drawingToken = try await client.uploadFile(png, filename: "drawing.png")
            save(record)
        }
        let drawingToken = record.drawingToken!

        // 2. Concept art: the AI's interpretation, in a rig-friendly pose.
        stage = .conceptArt
        if record.conceptFile == nil {
            do {
                if record.conceptTaskID == nil {
                    record.conceptTaskID = try await client.createTask("generation/image-to-image", body: [
                        "file": ["file_token": drawingToken],
                        "prompt": Self.prompt(description: record.description),
                    ])
                    save(record)
                }
                let conceptTask = try await client.waitForTask(record.conceptTaskID!, timeout: 300)
                if let imageURL = conceptTask.output?.primaryImageURL {
                    let imageData = try await client.download(imageURL)
                    if let image = UIImage(data: imageData) {
                        conceptImage = image
                        store.saveImage(image, named: Self.conceptFileName)
                        record.conceptFile = Self.conceptFileName
                        record.conceptImageURL = imageURL
                        save(record)
                    }
                } else {
                    note("Concept art returned no image — modeling from the raw drawing.", &record)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Concept stage is an enhancer, not a gate: fall back to the
                // raw drawing as the 3D input.
                note("Concept art skipped: \(error.localizedDescription)", &record)
            }
        }

        // 3. The 3D model itself.
        stage = .modeling
        if record.modelTaskID == nil {
            let modelInput = try await modelInput(for: record, client: client)
            record.modelTaskID = try await client.createTask("generation/image-to-model", body: [
                "file": modelInput,
                "model": Self.modelVersion,
                "texture": true,
                "pbr": true,
                // Without a face limit Tripo returns ~1.4M triangles — enough
                // to hang RealityKit on older phones. 60k renders identically
                // at creature size (the normal map carries the detail).
                "face_limit": 60_000,
            ])
            save(record)
        }
        let modelTaskID = record.modelTaskID!
        let modelTask = try await client.waitForTask(modelTaskID, timeout: 900)

        // 4. Rig + animations — best effort, never fatal.
        if record.convertTaskID == nil {
            do {
                stage = .rigging
                if record.rigType == nil, record.rigTaskID == nil {
                    if record.rigCheckTaskID == nil {
                        record.rigCheckTaskID = try await client.createTask("animations/rig-check", body: ["input": modelTaskID])
                        save(record)
                    }
                    let check = try await client.waitForTask(record.rigCheckTaskID!, timeout: 300)
                    if check.output?.riggable == false {
                        note("Not riggable — shipping a static model.", &record)
                        record.rigType = ""
                        save(record)
                    } else {
                        record.rigType = check.output?.recommendedRigType ?? check.output?.rigType ?? "quadruped"
                        save(record)
                    }
                }
                if let rigType = record.rigType, !rigType.isEmpty {
                    if record.rigTaskID == nil {
                        record.rigTaskID = try await client.createTask("animations/rig", body: [
                            "input": modelTaskID,
                            "rig_type": rigType,
                            "spec": "tripo",
                            "model": Self.rigModelVersion,
                        ])
                        save(record)
                    }
                    _ = try await client.waitForTask(record.rigTaskID!, timeout: 600)

                    stage = .animating
                    if record.retargetTaskID == nil {
                        // Preset naming differs across rig versions: some accept
                        // "preset:idle", others require "preset:<rigType>:idle".
                        // Try plain first, fall back to namespaced.
                        do {
                            record.retargetTaskID = try await client.createTask("animations/retarget", body: [
                                "input": record.rigTaskID!,
                                "animations": ["preset:idle", "preset:walk"],
                                "export_with_geometry": true,
                                "model": Self.rigModelVersion,
                            ])
                        } catch {
                            record.retargetTaskID = try await client.createTask("animations/retarget", body: [
                                "input": record.rigTaskID!,
                                "animations": ["preset:\(rigType):idle", "preset:\(rigType):walk"],
                                "export_with_geometry": true,
                                "model": Self.rigModelVersion,
                            ])
                        }
                        save(record)
                    }
                    _ = try await client.waitForTask(record.retargetTaskID!, timeout: 600)
                    record.animated = true
                    save(record)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Static model still ships.
                note("Animation skipped: \(error.localizedDescription)", &record)
                record.animated = false
                record.retargetTaskID = nil
                save(record)
            }
        }

        // 5. Export as USDZ (RealityKit's native format) and download.
        stage = .exporting
        let exportInput = record.animated ? (record.retargetTaskID ?? modelTaskID) : modelTaskID
        if record.convertTaskID == nil {
            record.convertTaskID = try await client.createTask("models/convert", body: [
                "input": exportInput,
                "format": "USDZ",
                "with_animation": record.animated,
            ])
            save(record)
        }
        let converted = try await client.waitForTask(record.convertTaskID!, timeout: 600)
        let modelPath = store.directory.appendingPathComponent(Self.modelFileName)

        guard let modelURL = converted.output?.primaryModelURL else {
            // Conversion produced nothing usable — try the raw model URL.
            if let raw = modelTask.output?.primaryModelURL, raw.lowercased().contains("usdz") {
                let data = try await client.download(raw)
                try data.write(to: modelPath, options: .atomic)
                return Result(conceptImageFile: record.conceptFile, modelFile: Self.modelFileName, animated: false)
            }
            throw TripoClient.TripoError.badResponse
        }
        let modelData = try await client.download(modelURL)
        // Sanity check: a USDZ is a zip and must start with "PK".
        guard modelData.count > 4, modelData[0] == 0x50, modelData[1] == 0x4B else {
            note("Downloaded model wasn't a valid USDZ (\(modelData.count) bytes) — URL may have expired.", &record)
            throw TripoClient.TripoError.badResponse
        }
        try modelData.write(to: modelPath, options: .atomic)

        return Result(conceptImageFile: record.conceptFile, modelFile: Self.modelFileName, animated: record.animated)
    }

    /// The image the 3D model is built from: the concept art when we have
    /// it (re-uploaded on resume, since Tripo's result URLs expire), else
    /// the raw drawing token.
    private func modelInput(for record: SpawnRecord, client: TripoClient) async throws -> [String: Any] {
        if let file = record.conceptFile,
           let image = GameStore.shared.loadImage(named: file),
           let png = image.pngData() {
            let token = try await client.uploadFile(png, filename: "concept.png")
            return ["file_token": token]
        }
        return ["file_token": record.drawingToken ?? ""]
    }
}
