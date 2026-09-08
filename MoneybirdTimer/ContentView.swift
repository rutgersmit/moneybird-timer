import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: TimerViewModel
    @StateObject private var quickActions = QuickActionCenter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                // MARK: Controls section
                Section {
                    projectPickerSection
                        .padding(.vertical, 8)
                    userPickerSection
                        .padding(.vertical, 8)

                    if viewModel.isRunning || viewModel.isPaused {
                        timerDisplay
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .transition(.scale.combined(with: .opacity))
                    }

                    actionButton
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))

                // MARK: Recent timers section
                Section {
                    if viewModel.isLoadingRecentTimers {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Laden\u{2026}")
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.recentTimers.isEmpty {
                        Text("Geen tijdregistraties gevonden.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(viewModel.recentTimers) { entry in
                            RecentTimerRow(entry: entry)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await viewModel.deleteRecentTimer(id: entry.id) }
                                    } label: {
                                        Label("Verwijderen", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if entry.ended_at != nil {
                                        Button {
                                            viewModel.editingEntry = entry
                                            viewModel.isShowingEditEntry = true
                                        } label: {
                                            Label("Wijzig", systemImage: "pencil")
                                        }
                                        .tint(.blue)

                                        if !viewModel.isRunning && !viewModel.isPaused {
                                            Button {
                                                Task { await viewModel.restartTimer(entry: entry) }
                                            } label: {
                                                Label("Hervat", systemImage: "play.fill")
                                            }
                                            .tint(.green)
                                        }
                                    }
                                }
                        }
                    }
                } header: {
                    Label("Recente tijdregistraties", systemImage: "clock")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .animation(.easeInOut(duration: 0.3), value: viewModel.isRunning)
            .navigationTitle("MoneybirdTimer")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }


            .sheet(isPresented: $viewModel.isShowingEditEntry) {
                if let entry = viewModel.editingEntry {
                    EditTimeEntryView(entry: entry)
                        .environmentObject(viewModel)
                }
            }
            .sheet(isPresented: $viewModel.isShowingSettings, onDismiss: {
                Task { await viewModel.loadAll() }
            }) {
                SettingsView()
                    .environmentObject(viewModel)
            }
            .alert("Fout", isPresented: $viewModel.isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                await viewModel.loadAll()
                handleQuickActionIfNeeded()
            }
            .onChange(of: quickActions.pending) { _ in
                handleQuickActionIfNeeded()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { handleQuickActionIfNeeded() }
            }
        }
    }

    /// Voert een via de Home Screen quick action aangevraagde actie uit.
    private func handleQuickActionIfNeeded() {
        guard let action = quickActions.pending else { return }
        quickActions.pending = nil
        switch action {
        case QuickAction.startRecentTimer:
            Task { await viewModel.startMostRecentTimer() }
        case QuickAction.stopRunningTimer:
            Task { await viewModel.stopTimer() }
        default:
            break
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var projectPickerSection: some View {
        pickerRow(
            label: "Project",
            icon: "folder.fill",
            isLoading: viewModel.isLoadingProjects,
            loadingText: "Projecten laden\u{2026}"
        ) {
            Picker("Project", selection: $viewModel.selectedProject) {
                Text("Selecteer een project").tag(Project?.none)
                ForEach(viewModel.projects) { project in
                    Text(project.name).tag(Project?.some(project))
                }
            }
            .onChange(of: viewModel.selectedProject) { newProject in
                if let project = newProject { viewModel.selectProject(project) }
            }
        }
        .disabled(viewModel.isRunning || viewModel.isPaused)
    }

    @ViewBuilder
    private var userPickerSection: some View {
        pickerRow(
            label: "Gebruiker",
            icon: "person.fill",
            isLoading: viewModel.isLoadingUsers,
            loadingText: "Gebruikers laden\u{2026}"
        ) {
            Picker("Gebruiker", selection: $viewModel.selectedUser) {
                Text("Selecteer een gebruiker").tag(User?.none)
                ForEach(viewModel.users) { user in
                    Text(user.name).tag(User?.some(user))
                }
            }
            .onChange(of: viewModel.selectedUser) { newUser in
                if let user = newUser { viewModel.selectUser(user) }
            }
        }
        .disabled(viewModel.isRunning || viewModel.isPaused)
    }

    @ViewBuilder
    private func pickerRow<P: View>(
        label: String,
        icon: String,
        isLoading: Bool,
        loadingText: String,
        @ViewBuilder picker: () -> P
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.headline)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(loadingText)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            } else {
                picker()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var timerDisplay: some View {
        let eightHours   = 8 * 3600
        let isOvertime   = viewModel.elapsedSeconds >= eightHours
        let mainProgress = min(1.0, CGFloat(viewModel.elapsedSeconds) / CGFloat(eightHours))
        let overtimeProgress = isOvertime
            ? min(1.0, CGFloat(viewModel.elapsedSeconds - eightHours) / CGFloat(eightHours))
            : 0.0
        let isPaused = viewModel.isPaused

        return ZStack {
            // Grijze achtergrondring
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 10)

            // Rode boog: loopt vol over 8 uur, blijft vol daarna
            Circle()
                .trim(from: 0, to: mainProgress)
                .stroke(isPaused ? Color.gray : Color.red, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: viewModel.elapsedSeconds)

            // Oranje boog: tweede ronde na 8 uur
            if isOvertime {
                Circle()
                    .trim(from: 0, to: overtimeProgress)
                    .stroke(isPaused ? Color.gray.opacity(0.6) : Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: viewModel.elapsedSeconds)
            }

            VStack(spacing: 4) {
                Text(viewModel.elapsedDisplay)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isPaused ? Color.secondary : (isOvertime ? Color.orange : Color.primary))
                    .contentTransition(.numericText())

                if isPaused {
                    Label("Gepauzeerd", systemImage: "pause.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 210, height: 210)
    }

    private var actionButton: some View {
        let canStart = viewModel.isNetworkAvailable

        return HStack(spacing: 12) {
            if viewModel.isRunning {
                Button {
                    Task { await viewModel.pauseTimer() }
                } label: {
                    Label("Pauze", systemImage: "pause.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 130, minHeight: 60)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
                }
            } else if viewModel.isPaused {
                Button {
                    Task { await viewModel.resumeTimer() }
                } label: {
                    Label("Hervat", systemImage: "play.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 130, minHeight: 60)
                        .background(canStart ? Color.green : Color.gray, in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!canStart)
            } else {
                Button {
                    Task { await viewModel.startTimer() }
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 130, minHeight: 60)
                        .background(canStart ? Color.green : Color.gray, in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!canStart)
            }

            if viewModel.isRunning || viewModel.isPaused {
                Button {
                    Task { await viewModel.stopTimer() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 90, minHeight: 60)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRunning)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPaused)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isNetworkAvailable)
    }


}

// MARK: - Recent timer row

private struct RecentTimerRow: View {
    let entry: TimeEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.project?.name ?? "Onbekend project")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let userName = entry.user?.name {
                        Text(userName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(dateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(durationLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(entry.ended_at == nil ? Color.red : Color.primary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var durationLabel: String {
        guard let startDate = parseISO8601(entry.started_at) else { return "--:--" }
        let endDate = entry.ended_at.flatMap { parseISO8601($0) } ?? Date()
        let secs = max(0, Int(endDate.timeIntervalSince(startDate)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return entry.ended_at == nil
            ? String(format: "%d:%02d ●", h, m)
            : String(format: "%d:%02d", h, m)
    }

    private var dateLabel: String {
        guard let startDate = parseISO8601(entry.started_at) else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "nl_NL")
        return formatter.string(from: startDate)
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
