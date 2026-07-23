import SwiftUI

struct EditTimeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: TimerViewModel

    let entry: TimeEntry

    @State private var selectedStart: Date
    @State private var selectedEnd: Date
    @State private var isSaving = false

    init(entry: TimeEntry) {
        self.entry = entry
        let start = Self.parseISO8601(entry.started_at) ?? Date()
        let end   = Self.parseISO8601(entry.ended_at ?? "") ?? Date()
        _selectedStart = State(initialValue: start)
        _selectedEnd   = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Begintijd") {
                    DatePicker(
                        "Begintijd",
                        selection: $selectedStart,
                        in: ...selectedEnd.addingTimeInterval(-60),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .onChange(of: selectedStart) { newStart in
                        if selectedEnd <= newStart.addingTimeInterval(60) {
                            selectedEnd = newStart.addingTimeInterval(60)
                        }
                    }
                }

                Section("Eindtijd") {
                    DatePicker(
                        "Eindtijd",
                        selection: $selectedEnd,
                        in: selectedStart.addingTimeInterval(60)...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                }

                Section("Duur") {
                    Text(durationLabel)
                        .font(.headline.monospacedDigit())
                }
            }
            .navigationTitle("Tijdregistratie aanpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Opslaan") {
                            isSaving = true
                            Task {
                                await viewModel.updateRecentTimer(
                                    id: entry.id,
                                    startedAt: selectedStart,
                                    endedAt: selectedEnd
                                )
                                isSaving = false
                                dismiss()
                            }
                        }
                        .bold()
                    }
                }
            }
        }
    }

    private var durationLabel: String {
        let secs = max(0, Int(selectedEnd.timeIntervalSince(selectedStart)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return String(format: "%d:%02d uur", h, m)
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
