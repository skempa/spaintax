import Foundation
import UIKit
import PencilKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Turns a freehand drawing into a game-ready creature.
///
/// The MVP ships with `HeuristicCreatureGenerator`: fully on-device,
/// instant, and deterministic enough that the result visibly comes from
/// the drawing. The protocol exists so a server-side image model (drawing
/// → stylised creature art) can replace it without touching the rest of
/// the game — swap the instance in `AppState`.
protocol CreatureGenerating {
    func generate(from drawing: PKDrawing, canvasSize: CGSize, name: String) async throws -> Creature
}

struct HeuristicCreatureGenerator: CreatureGenerating {

    func generate(from drawing: PKDrawing, canvasSize: CGSize, name: String) async throws -> Creature {
        let analysis = analyse(drawing: drawing, canvasSize: canvasSize)
        let core = assignCore(for: analysis)

        // Render and persist both the untouched original and the
        // game-styled version.
        let originalImage = drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: 2)
        let processedImage = stylise(originalImage, analysis: analysis, core: core)

        let originalFile = "creature-original.png"
        let processedFile = "creature-processed.png"
        GameStore.shared.saveImage(originalImage, named: originalFile)
        GameStore.shared.saveImage(processedImage, named: processedFile)

        let appearance = CreatureAppearance(
            originalDrawingFile: originalFile,
            processedImageFile: processedFile,
            baseHue: analysis.dominantHue ?? core.fallbackHue,
            roundness: min(1.0, analysis.symmetry * 0.6 + analysis.inkCoverage * 0.8),
            scale: 0.8 + analysis.inkCoverage * 0.5
        )

        return Creature(name: name, appearance: appearance, analysis: analysis, firstCore: core)
    }

    // MARK: - Feature extraction

    func analyse(drawing: PKDrawing, canvasSize: CGSize) -> DrawingAnalysis {
        let strokes = drawing.strokes
        let bounds = drawing.bounds

        let canvasArea = max(canvasSize.width * canvasSize.height, 1)
        let coverage = Double((bounds.width * bounds.height) / canvasArea)
        let aspect = bounds.height > 0 ? Double(bounds.width / bounds.height) : 1.0

        // Colour features.
        var hues: [Double] = []
        var colorSet = Set<String>()
        for stroke in strokes {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            stroke.ink.color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            if s > 0.15 && b > 0.1 { hues.append(Double(h) * 360) }
            colorSet.insert(String(format: "%.1f-%.1f-%.1f", h, s, b))
        }
        let dominantHue = dominantHueByBucket(hues)

        // Jaggedness: mean absolute direction change along stroke paths.
        var directionChanges: [Double] = []
        for stroke in strokes {
            let points = stroke.path.map(\.location)
            guard points.count > 2 else { continue }
            var previousAngle: Double?
            for i in 1..<points.count {
                let dx = Double(points[i].x - points[i - 1].x)
                let dy = Double(points[i].y - points[i - 1].y)
                guard abs(dx) + abs(dy) > 0.5 else { continue }
                let angle = atan2(dy, dx)
                if let prev = previousAngle {
                    var delta = abs(angle - prev)
                    if delta > .pi { delta = 2 * .pi - delta }
                    directionChanges.append(delta)
                }
                previousAngle = angle
            }
        }
        let jaggedness = directionChanges.isEmpty
            ? 0.0
            : min(1.0, (directionChanges.reduce(0, +) / Double(directionChanges.count)) / (.pi / 2))

        // Symmetry: compare stroke-point density between the left and
        // right halves of the bounding box.
        let midX = bounds.midX
        var left = 0, right = 0
        for stroke in strokes {
            for point in stroke.path {
                if point.location.x < midX { left += 1 } else { right += 1 }
            }
        }
        let total = max(left + right, 1)
        let symmetry = 1.0 - abs(Double(left - right)) / Double(total)

        var impressions: [String] = []
        if aspect > 1.4 { impressions.append("wide stance") }
        if aspect < 0.7 { impressions.append("tall and slender") }
        if strokes.count > 25 { impressions.append("rich in detail") }
        if jaggedness > 0.5 { impressions.append("wild, energetic lines") }
        if symmetry > 0.85 { impressions.append("strikingly balanced") }
        if colorSet.count > 4 { impressions.append("a riot of colour") }

        return DrawingAnalysis(
            inkCoverage: min(1.0, coverage),
            aspectRatio: aspect,
            strokeCount: strokes.count,
            dominantHue: dominantHue,
            colorCount: colorSet.count,
            symmetry: symmetry,
            jaggedness: jaggedness,
            impressions: impressions
        )
    }

    private func dominantHueByBucket(_ hues: [Double]) -> Double? {
        guard !hues.isEmpty else { return nil }
        var buckets: [Int: Int] = [:]
        for hue in hues { buckets[Int(hue / 30), default: 0] += 1 }
        guard let best = buckets.max(by: { $0.value < $1.value }) else { return nil }
        let inBucket = hues.filter { Int($0 / 30) == best.key }
        return inBucket.reduce(0, +) / Double(inBucket.count)
    }

    // MARK: - Core assignment

    /// The player does not choose the first Core — the drawing does.
    /// Each Core scores against the drawing's characteristics; a small
    /// random jitter keeps the outcome exciting rather than fully
    /// predictable.
    func assignCore(for analysis: DrawingAnalysis) -> ElementalCore {
        var scores: [ElementalCore: Double] = [:]

        for core in ElementalCore.allCases {
            var score = Double.random(in: 0...0.35)   // unpredictability
            if let hue = analysis.dominantHue {
                score += hueAffinity(hue: hue, core: core)
            }
            switch core {
            case .storm:   score += analysis.jaggedness * 0.8
            case .crystal: score += analysis.symmetry * 0.6 + analysis.inkCoverage * 0.3
            case .ember:   score += analysis.jaggedness * 0.4 + (analysis.aspectRatio > 1.2 ? 0.2 : 0)
            case .aqua:    score += (1 - analysis.jaggedness) * 0.5
            case .verdant: score += min(Double(analysis.strokeCount) / 40.0, 1.0) * 0.5
            case .void:    score += (1 - analysis.symmetry) * 0.5 + (analysis.colorCount <= 1 ? 0.3 : 0)
            }
            scores[core] = score
        }

        return scores.max(by: { $0.value < $1.value })?.key ?? .ember
    }

    private func hueAffinity(hue: Double, core: ElementalCore) -> Double {
        func closeness(to target: Double) -> Double {
            var d = abs(hue - target)
            if d > 180 { d = 360 - d }
            return max(0, 1 - d / 60)   // full affinity at the target, fading over 60°
        }
        switch core {
        case .ember:   return closeness(to: 15)    // reds / oranges
        case .storm:   return closeness(to: 55)    // yellows
        case .verdant: return closeness(to: 120)   // greens
        case .aqua:    return closeness(to: 210)   // blues
        case .void:    return closeness(to: 275)   // purples
        case .crystal: return closeness(to: 190)   // cyans / pale blues
        }
    }

    // MARK: - Stylisation

    /// Applies the game's visual style while preserving recognisable
    /// aspects of the original: soft bloom, Core-tinted rim, gentle
    /// posterisation. "I drew that, and now it's alive."
    private func stylise(_ image: UIImage, analysis: DrawingAnalysis, core: ElementalCore) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        let context = CIContext()

        let posterize = CIFilter.colorPosterize()
        posterize.inputImage = ciImage
        posterize.levels = 8

        let bloom = CIFilter.bloom()
        bloom.inputImage = posterize.outputImage ?? ciImage
        bloom.intensity = 0.6
        bloom.radius = 8

        guard let output = bloom.outputImage,
              let cgImage = context.createCGImage(output, from: ciImage.extent) else {
            return image
        }
        return UIImage(cgImage: cgImage)
    }
}

private extension ElementalCore {
    /// Hue used when the drawing is monochrome.
    var fallbackHue: Double {
        switch self {
        case .ember: return 15
        case .storm: return 55
        case .verdant: return 120
        case .crystal: return 190
        case .aqua: return 210
        case .void: return 275
        }
    }
}
