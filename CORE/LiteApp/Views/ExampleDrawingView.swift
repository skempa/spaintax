import SwiftUI

/// A little creature being drawn stroke by stroke, on loop — shows what
/// "draw a creature" means without a word of copy. Crayon-ish strokes:
/// round caps, slight wobble, orange body with a green tuft.
struct ExampleDrawingView: View {
    var lineWidth: CGFloat = 7
    @State private var progress: CGFloat = 0

    /// Strokes in drawing order, each with its colour and its share of the
    /// total timeline (start, end) in 0…1.
    private var strokes: [(path: Path, color: Color, range: ClosedRange<CGFloat>)] {
        [
            (Self.body,     Theme.crayonOrange, 0.00...0.42),
            (Self.leftLeg,  Theme.crayonOrange, 0.42...0.52),
            (Self.rightLeg, Theme.crayonOrange, 0.52...0.62),
            (Self.leftEar,  Theme.crayonOrange, 0.62...0.70),
            (Self.rightEar, Theme.crayonOrange, 0.70...0.78),
            (Self.tuft,     Theme.crayonGreen,  0.78...0.86),
            (Self.eyes,     Theme.ink,          0.86...0.92),
            (Self.grin,     Theme.ink,          0.92...1.00),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 200
            ZStack {
                ForEach(strokes.indices, id: \.self) { i in
                    let s = strokes[i]
                    let local = ((progress - s.range.lowerBound) / (s.range.upperBound - s.range.lowerBound))
                        .clamped(to: 0...1)
                    s.path
                        .applying(CGAffineTransform(scaleX: scale, y: scale))
                        .trimmedPath(from: 0, to: local)
                        .stroke(s.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        .opacity(0.92)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { animate() }
    }

    private func animate() {
        progress = 0
        withAnimation(.easeInOut(duration: 3.2)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            withAnimation(.easeOut(duration: 0.4)) { progress = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { animate() }
        }
    }

    // MARK: Strokes (200×200 design space)

    private static var body: Path {
        var p = Path()
        p.move(to: CGPoint(x: 62, y: 70))
        p.addCurve(to: CGPoint(x: 140, y: 72), control1: CGPoint(x: 80, y: 42), control2: CGPoint(x: 126, y: 44))
        p.addCurve(to: CGPoint(x: 150, y: 138), control1: CGPoint(x: 160, y: 96), control2: CGPoint(x: 164, y: 122))
        p.addCurve(to: CGPoint(x: 62, y: 140), control1: CGPoint(x: 132, y: 160), control2: CGPoint(x: 78, y: 162))
        p.addCurve(to: CGPoint(x: 62, y: 70), control1: CGPoint(x: 42, y: 122), control2: CGPoint(x: 44, y: 92))
        return p
    }
    private static var leftLeg: Path {
        var p = Path()
        p.move(to: CGPoint(x: 84, y: 150)); p.addLine(to: CGPoint(x: 80, y: 176))
        p.addLine(to: CGPoint(x: 92, y: 178))
        return p
    }
    private static var rightLeg: Path {
        var p = Path()
        p.move(to: CGPoint(x: 124, y: 150)); p.addLine(to: CGPoint(x: 128, y: 176))
        p.addLine(to: CGPoint(x: 140, y: 178))
        return p
    }
    private static var leftEar: Path {
        var p = Path()
        p.move(to: CGPoint(x: 72, y: 62)); p.addLine(to: CGPoint(x: 66, y: 34)); p.addLine(to: CGPoint(x: 90, y: 50))
        return p
    }
    private static var rightEar: Path {
        var p = Path()
        p.move(to: CGPoint(x: 130, y: 62)); p.addLine(to: CGPoint(x: 138, y: 34)); p.addLine(to: CGPoint(x: 114, y: 50))
        return p
    }
    private static var tuft: Path {
        var p = Path()
        p.move(to: CGPoint(x: 100, y: 46)); p.addQuadCurve(to: CGPoint(x: 96, y: 26), control: CGPoint(x: 90, y: 34))
        p.move(to: CGPoint(x: 102, y: 46)); p.addQuadCurve(to: CGPoint(x: 112, y: 28), control: CGPoint(x: 112, y: 36))
        return p
    }
    private static var eyes: Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 82, y: 86, width: 6, height: 6))
        p.addEllipse(in: CGRect(x: 112, y: 86, width: 6, height: 6))
        return p
    }
    private static var grin: Path {
        var p = Path()
        p.move(to: CGPoint(x: 80, y: 112))
        p.addQuadCurve(to: CGPoint(x: 122, y: 112), control: CGPoint(x: 101, y: 130))
        return p
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
