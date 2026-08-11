import Foundation

/// Features extracted from the player's freehand drawing.
///
/// This is the structured output of creature generation: the on-device
/// heuristic analyser fills it in immediately, and a server-side AI
/// generator can replace or enrich it later (see `CreatureGenerating`).
struct DrawingAnalysis: Codable, Equatable {
    /// 0–1: how much of the canvas the drawing covers.
    var inkCoverage: Double
    /// Width / height of the drawing's bounding box.
    var aspectRatio: Double
    /// Number of strokes the player drew.
    var strokeCount: Int
    /// Dominant hue of the drawing, in degrees 0–360 (nil if monochrome).
    var dominantHue: Double?
    /// Number of distinct colours used.
    var colorCount: Int
    /// 0–1: estimated left/right symmetry of the silhouette.
    var symmetry: Double
    /// 0–1: how jagged/energetic the strokes are (fast direction changes).
    var jaggedness: Double
    /// Short human-readable impressions, e.g. "wide stance", "many limbs".
    var impressions: [String]

    static let placeholder = DrawingAnalysis(
        inkCoverage: 0.3, aspectRatio: 1.0, strokeCount: 12,
        dominantHue: nil, colorCount: 1, symmetry: 0.5,
        jaggedness: 0.3, impressions: []
    )
}

/// Visual parameters for rendering the generated creature.
/// Derived from the drawing so the result preserves recognisable aspects
/// of the original: "I drew that, and now it's alive."
struct CreatureAppearance: Codable, Equatable {
    /// File name of the player's original drawing (PNG in the store directory).
    var originalDrawingFile: String
    /// File name of the processed, game-styled creature image.
    var processedImageFile: String
    /// Base hue used for auras and accents, 0–360.
    var baseHue: Double
    /// Body roundness 0–1 (from ink coverage + symmetry).
    var roundness: Double
    /// Overall scale factor for AR placement, roughly 0.8–1.3.
    var scale: Double
}
