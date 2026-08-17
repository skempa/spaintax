import SwiftUI

/// The active ritual: pick a duration, put the phone down, and your
/// creature grows from your focus. Locking the phone keeps the session
/// running; wandering into other apps ends it (completed minutes still
/// bank — recoverable, never punitive).
struct FocusSessionView: View {
    @EnvironmentObject private var app: LiteAppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            switch app.focusPhase {
            case .idle:
                picker
            case .running:
                running
            case .finished(let points, let completed):
                finished(points: points, completed: completed)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.04, green: 0.09, blue: 0.07))
        .foregroundStyle(.white)
        .interactiveDismissDisabled(isRunning)
    }

    private var isRunning: Bool {
        if case .running = app.focusPhase { return true }
        return false
    }

    // MARK: Duration picker

    private var picker: some View {
        VStack(spacing: 20) {
            Text("Focus Session")
                .font(.title.bold())
                .padding(.top, 20)
            Text("Put the phone down — lock it, flip it over, walk away. \(app.creature?.name ?? "Your creature") grows while you focus.\n\n1 Growth Point per \(Tuning.focusMinutesPerPoint) minutes.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            ForEach(Tuning.focusSessionLengths, id: \.self) { minutes in
                Button {
                    app.startFocus(minutes: minutes)
                } label: {
                    HStack {
                        Text("\(minutes) minutes")
                            .font(.headline)
                        Spacer()
                        Text("+\(minutes / Tuning.focusMinutesPerPoint) pts")
                            .font(.subheadline)
                            .foregroundStyle(.mint)
                    }
                    .padding()
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }

            Spacer()
            Button("Not now") { dismiss() }
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, 16)
        }
    }

    // MARK: Running

    private var running: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.1), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(.mint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 6) {
                    Text(timeString)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(app.creature?.name ?? "It") is growing…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 240, height: 240)
            .animation(.linear(duration: 1), value: progressFraction)

            Text("Lock the phone — the session keeps running.\nSwitching to other apps ends it.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Spacer()

            Button("Give up (keep completed minutes)") {
                app.abandonFocus()
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.5))
            .padding(.bottom, 16)
        }
    }

    private var progressFraction: CGFloat {
        guard case .running(let endsAt) = app.focusPhase,
              let record = app.lite.activeFocus else { return 0 }
        let total = endsAt.timeIntervalSince(record.startedAt)
        guard total > 0 else { return 0 }
        return CGFloat(1 - app.focusRemaining / total)
    }

    private var timeString: String {
        let seconds = Int(app.focusRemaining.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Finished

    private func finished(points: Int, completed: Bool) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Text(completed ? "🌿" : "🍃").font(.system(size: 72))
            Text(completed ? "Session complete!" : "Session ended early")
                .font(.title2.bold())
            Text(points > 0
                 ? "+\(points) Growth Points for \(app.creature?.name ?? "your creature")"
                 : "No points this time — even a few focused minutes count next time.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                app.dismissFocusResult()
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(.black)
            }
            .padding(.bottom, 16)
        }
    }
}
