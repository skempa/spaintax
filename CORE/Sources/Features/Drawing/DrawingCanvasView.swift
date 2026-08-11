import SwiftUI
import PencilKit

/// What the player hands to the generator.
struct DrawingSubmission {
    let drawing: PKDrawing
    let canvasSize: CGSize
    let name: String
}

/// Freehand finger-drawing canvas. Encourages creativity, offers only
/// gentle guidance: "Draw your companion."
struct DrawingCanvasView: View {
    @EnvironmentObject private var appState: AppState

    @State private var canvasView = PKCanvasView()
    @State private var selectedColor: Color = .white
    @State private var strokeWidth: CGFloat = 8
    @State private var canvasSize: CGSize = .zero
    @State private var showNamePrompt = false
    @State private var creatureName = ""
    @State private var hasInk = false

    private let palette: [Color] = [
        .white, .red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink, .brown
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Draw your companion")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.top, 16)
            Text("Anything goes. It will come to life exactly as you imagine it.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 12)

            GeometryReader { geo in
                CanvasRepresentable(
                    canvasView: $canvasView,
                    color: UIColor(selectedColor),
                    width: strokeWidth,
                    onDrawingChanged: { hasInk = !canvasView.drawing.strokes.isEmpty }
                )
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
            }
            .padding(.horizontal, 16)

            // Palette + tools
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(palette.indices, id: \.self) { index in
                        let color = palette[index]
                        Circle()
                            .fill(color)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(.white, lineWidth: selectedColor == color ? 3 : 0))
                            .onTapGesture { selectedColor = color }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 50)
            .padding(.top, 12)

            HStack(spacing: 20) {
                Slider(value: $strokeWidth, in: 3...24) {
                    Text("Stroke width")
                }
                .frame(width: 140)
                .tint(.white.opacity(0.7))

                Button("Undo") { canvasView.undoManager?.undo() }
                Button("Clear") {
                    canvasView.drawing = PKDrawing()
                    hasInk = false
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.vertical, 8)

            Button {
                showNamePrompt = true
            } label: {
                Text("Bring it to life")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(hasInk ? Color.white : Color.gray.opacity(0.4), in: Capsule())
                    .foregroundStyle(.black)
            }
            .disabled(!hasInk)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .alert("Name your companion", isPresented: $showNamePrompt) {
            TextField("Name", text: $creatureName)
            Button("Create") {
                let name = creatureName.trimmingCharacters(in: .whitespaces)
                appState.createCreature(from: DrawingSubmission(
                    drawing: canvasView.drawing,
                    canvasSize: canvasSize,
                    name: name.isEmpty ? "Companion" : name
                ))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is permanent — your companion stays with you.")
        }
        .alert("Generation failed", isPresented: .constant(appState.generationError != nil)) {
            Button("OK") { appState.generationError = nil }
        } message: {
            Text(appState.generationError ?? "")
        }
    }
}

/// PencilKit wrapper configured for finger drawing.
private struct CanvasRepresentable: UIViewRepresentable {
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
