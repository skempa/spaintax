import SwiftUI
import PencilKit

/// What the player hands to the creature generator.
struct DrawingSubmission {
    let drawing: PKDrawing
    let canvasSize: CGSize
    let name: String
}

/// PencilKit wrapper configured for finger drawing. Shared by the full
/// game's drawing screen and CORE Lite's.
struct CanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let color: UIColor
    let width: CGFloat
    let onDrawingChanged: () -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.tool = PKInkingTool(.marker, color: color, width: width)
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        view.tool = PKInkingTool(.marker, color: color, width: width)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onDrawingChanged) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onChange: () -> Void
        init(onChange: @escaping () -> Void) { self.onChange = onChange }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { onChange() }
    }
}
