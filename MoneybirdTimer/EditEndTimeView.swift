import SwiftUI

// MARK: - Sheet

struct EditEndTimeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: TimerViewModel

    @State private var selectedEnd: Date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("Wanneer heb je gestopt?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let start = viewModel.timerStartDate {
                    CircularEndTimePicker(startDate: start, now: Date(), selection: $selectedEnd)
                        .padding(.horizontal, 28)

                    infoRow(start: start)
                }

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Eindtijd aanpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Stoppen") {
                        Task {
                            await viewModel.stopTimer(endedAt: selectedEnd)
                            dismiss()
                        }
                    }
                    .bold()
                    .tint(.red)
                }
            }
            .onAppear { selectedEnd = Date() }
        }
    }

    private func infoRow(start: Date) -> some View {
        HStack(spacing: 0) {
            timeCell(title: "Gestart", date: start)
            Spacer()
            timeCell(title: "Eindtijd", date: selectedEnd)
            Spacer()
            durationCell(from: start, to: selectedEnd)
        }
        .padding(.horizontal, 32)
    }

    private func timeCell(title: String, date: Date) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(date, style: .time)
                .font(.headline.monospacedDigit())
        }
    }

    private func durationCell(from start: Date, to end: Date) -> some View {
        let secs = max(0, Int(end.timeIntervalSince(start)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return VStack(spacing: 4) {
            Text("Duur")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%d:%02d", h, m))
                .font(.headline.monospacedDigit())
        }
    }
}

// MARK: - Circular picker

struct CircularEndTimePicker: View {
    let startDate: Date
    let now: Date
    @Binding var selection: Date

    @State private var previousAngle: Double?

    private let lineWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let size   = min(geo.size.width, geo.size.height)
            let radius = size / 2 - lineWidth / 2
            let frac   = selectedFraction
            // Handle position: angle 0 = top (12 o'clock), clockwise
            let rad = frac * 2 * .pi - .pi / 2
            let hx  = size / 2 + radius * cos(rad)
            let hy  = size / 2 + radius * sin(rad)

            ZStack {
                // Background track
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)
                    .padding(lineWidth / 2)

                // Progress arc (start → selected end)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .padding(lineWidth / 2)
                    .rotationEffect(.degrees(-90))

                // Centre: selected time + duration
                VStack(spacing: 6) {
                    Text(selection, style: .time)
                        .font(.system(size: 36, weight: .semibold, design: .monospaced))
                    Text(durationLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Draggable handle
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(Color.red, lineWidth: 3))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .frame(width: 30, height: 30)
                    .position(x: hx, y: hy)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in updateSelection(at: drag.location, size: size) }
                    .onEnded   { _    in previousAngle = nil }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Helpers

    private var selectedFraction: Double {
        let total = now.timeIntervalSince(startDate)
        guard total > 0 else { return 0 }
        return max(0.001, min(0.999, selection.timeIntervalSince(startDate) / total))
    }

    private var durationLabel: String {
        let secs = max(0, Int(selection.timeIntervalSince(startDate)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return String(format: "%d:%02d uur", h, m)
    }

    /// Delta-based update so the handle never "teleports" near 0°/360°.
    private func updateSelection(at point: CGPoint, size: CGFloat) {
        let center = CGPoint(x: size / 2, y: size / 2)
        // atan2(x, -y) gives clockwise angle from the top
        var angle = atan2(point.x - center.x, -(point.y - center.y))
        if angle < 0 { angle += 2 * .pi }

        let total = now.timeIntervalSince(startDate)

        if let prev = previousAngle {
            var delta = angle - prev
            if delta >  .pi { delta -= 2 * .pi }   // wrap-around clockwise
            if delta < -.pi { delta += 2 * .pi }   // wrap-around counter-clockwise
            let deltaTime = delta / (2 * .pi) * total
            let current   = selection.timeIntervalSince(startDate)
            let clamped   = max(60, min(total, current + deltaTime))
            selection = startDate.addingTimeInterval(clamped)
        }
        previousAngle = angle
    }
}
