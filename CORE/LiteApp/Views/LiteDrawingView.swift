import SwiftUI
import PencilKit

/// Freehand drawing canvas — Lite variant of the full game's screen,
/// built on the shared CanvasRepresentable.
struct LiteDrawingView: View {
    @EnvironmentObject private var app: LiteAppState

    @State private var canvasView = PKCanvasView()
    @State private var selectedColor: Color = Theme.crayonOrange
    @State private var strokeWidth: CGFloat = 10
    @State private var canvasSize: CGSize = .zero
    @State private var showNamePrompt = false
    @State private var creatureName = ""
    @State private var hasInk = false
    @State private var showSettings = false

    private let palette: [Color] = [
        Theme.ink, .red, Theme.crayonOrange, .yellow, Theme.crayonGreen, .mint, .cyan, Theme.crayonBlue, .purple, .pink, .brown
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Text("Draw your companion")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            Text("A blob with legs is perfect. Fill it with colour for a richer creature.")
                .font(.footnote)
                .foregroundStyle(Theme.inkDim)

            GeometryReader { geo in
                CanvasRepresentable(
                    canvasView: $canvasView,
                    color: UIColor(selectedColor),
                    width: strokeWidth,
                    onDrawingChanged: { hasInk = !canvasView.drawing.strokes.isEmpty }
                )
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.inkFaint.opacity(0.4), lineWidth: 1))
                .overlay {
                    if !hasInk {
                        VStack(spacing: 10) {
                            ExampleDrawingView(lineWidth: 6)
                                .frame(width: 150, height: 150)
                            Text("Something like this")
                                .font(.footnote)
                                .foregroundStyle(Theme.inkFaint)
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: hasInk)
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
                            .overlay(Circle().stroke(Theme.ink, lineWidth: selectedColor == color ? 3 : 0))
                            .overlay(Circle().stroke(Theme.inkFaint.opacity(0.4), lineWidth: 1))
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
            .foregroundStyle(Theme.inkDim)

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
        .background(Theme.paper.ignoresSafeArea())
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
