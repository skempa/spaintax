import SwiftUI
import PencilKit

/// Freehand drawing canvas — Lite variant of the full game's screen,
/// built on the shared CanvasRepresentable.
struct LiteDrawingView: View {
    @EnvironmentObject private var app: LiteAppState

    @State private var canvasView = PKCanvasView()
    @State private var selectedColor: Color = .white
    @State private var strokeWidth: CGFloat = 10
    @State private var canvasSize: CGSize = .zero
    @State private var showNamePrompt = false
    @State private var creatureName = ""
    @State private var hasInk = false
    @State private var showSettings = false

    private let palette: [Color] = [
        .white, .red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink, .brown
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Text("Draw your companion")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            Text("A blob with legs is perfect. Fill it with colour for a richer creature.")
                .font(.footnote)
                .foregroundStyle(Theme.textDim)

            GeometryReader { geo in
                CanvasRepresentable(
                    canvasView: $canvasView,
                    color: UIColor(selectedColor),
                    width: strokeWidth,
                    onDrawingChanged: { hasInk = !canvasView.drawing.strokes.isEmpty }
                )
                .background(Theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(palette.indices, id: \.self) { index in
                        let color = palette[index]
                        Circle()
                            .fill(color)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Theme.accent, lineWidth: selectedColor == color ? 3 : 0))
                            .onTapGesture { selectedColor = color }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 44)

            HStack(spacing: 20) {
                Slider(value: $strokeWidth, in: 3...26)
                    .frame(width: 140)
                    .tint(Theme.accent)
                Button("Undo") { canvasView.undoManager?.undo() }
                Button("Clear") { canvasView.drawing = PKDrawing(); hasInk = false }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textDim)

            Button {
                showNamePrompt = true
            } label: {
                Text("Bring it to life")
            }
            .buttonStyle(.primary)
            .disabled(!hasInk)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .alert("Name your companion", isPresented: $showNamePrompt) {
            TextField("Name", text: $creatureName)
            Button("Create") {
                let name = creatureName.trimmingCharacters(in: .whitespaces)
                app.createCreature(from: DrawingSubmission(
                    drawing: canvasView.drawing,
                    canvasSize: canvasSize,
                    name: name.isEmpty ? "Companion" : name
                ))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is permanent — your companion stays with you.")
        }
        .alert("Generation failed", isPresented: .constant(app.generationError != nil)) {
            Button("OK") { app.generationError = nil }
        } message: {
            Text(app.generationError ?? "")
        }
        .sheet(isPresented: $showSettings) { LiteSettingsView() }
    }
}
