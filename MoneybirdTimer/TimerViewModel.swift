import Foundation
import Combine
import Network
import UserNotifications

enum UDKey {
    static let timeEntryId = "activeTimeEntryId"
    static let startedAt = "activeTimerStartedAt"
    static let selectedProjectId = "selectedProjectId"
    static let selectedProjectName = "selectedProjectName"
    static let selectedUserId = "selectedUserId"
}

@MainActor
final class TimerViewModel: ObservableObject {
    // MARK: - Published state

    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    @Published var isLoadingProjects = false

    @Published var users: [User] = []
    @Published var selectedUser: User?
    @Published var isLoadingUsers = false

    @Published var recentTimers: [TimeEntry] = []
    @Published var isLoadingRecentTimers = false
    @Published var editingEntry: TimeEntry?
    @Published var isShowingEditEntry = false

    @Published var isRunning = false
    @Published var elapsedSeconds: Int = 0
    @Published var errorMessage: String?
    @Published var isShowingError = false
    @Published var isShowingSettings = false
    @Published var isNetworkAvailable = true

    // MARK: - Private state

    private var ticker: Timer?
    private var startDate: Date?
    private var activeEntryId: String?
    private var cancellables = Set<AnyCancellable>()
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")

    // MARK: - Init

    init() {
        restoreTimerIfNeeded()
        startNetworkMonitoring()
        NotificationCenter.default.publisher(for: .timerStoppedViaNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.clearTimerState() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public interface

    func loadAll() async {
        await loadProjects()
        await loadUsers()
        await loadRecentTimers()
    }

    func loadProjects() async {
        isLoadingProjects = true
        defer { isLoadingProjects = false }
        do {
            let fetched = try await MoneybirdAPI.shared.fetchProjects()
            projects = fetched
                .filter { $0.isActive }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            restoreSelectedProject()
        } catch let error as APIError {
            if case .missingCredentials = error {
                isShowingSettings = true
            } else {
                presentError(error.localizedDescription)
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func loadUsers() async {
        isLoadingUsers = true
        defer { isLoadingUsers = false }
        do {
            let fetched = try await MoneybirdAPI.shared.fetchUsers()
            users = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            restoreSelectedUser()
        } catch let error as APIError {
            if case .missingCredentials = error {
                isShowingSettings = true
            } else {
                presentError(error.localizedDescription)
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func startTimer() async {
        guard let project = selectedProject else {
            presentError("Selecteer eerst een project.")
            return
        }
        guard let user = selectedUser else {
            presentError("Selecteer eerst een gebruiker.")
            return
        }
        await startTimer(projectId: project.id, userId: user.id)
    }

    /// Start een timer met het laatst gebruikte project en gebruiker.
    /// Wordt aangeroepen vanuit de Home Screen quick action. Leest de ID's
    /// synchroon uit UserDefaults, zodat dit ook werkt bij een koude start
    /// voordat projecten/gebruikers geladen zijn. Valt terug op de recentste
    /// tijdregistratie wanneer er nog geen selectie bewaard is.
    func startMostRecentTimer() async {
        guard !isRunning else { return }

        let projectId = selectedProject?.id
            ?? UserDefaults.standard.string(forKey: UDKey.selectedProjectId)
            ?? recentTimers.first?.project_id
        let userId = selectedUser?.id
            ?? UserDefaults.standard.string(forKey: UDKey.selectedUserId)
            ?? recentTimers.first?.user_id

        guard let projectId, let userId else {
            presentError("Nog geen recent project of gebruiker bekend. Start eerst een timer in de app.")
            return
        }
        await startTimer(projectId: projectId, userId: userId)
    }

    private func startTimer(projectId: String, userId: String) async {
        do {
            let entry = try await MoneybirdAPI.shared.startTimer(projectId: projectId, userId: userId)
            activeEntryId = entry.id
            startDate = parseISO8601(entry.started_at) ?? Date()

            UserDefaults.standard.set(entry.id, forKey: UDKey.timeEntryId)
            UserDefaults.standard.set(entry.started_at, forKey: UDKey.startedAt)

            isRunning = true
            syncQuickActions()
            scheduleNotification(from: startDate!)
            startTicker()
        } catch let error as APIError {
            if case .missingCredentials = error {
                isShowingSettings = true
            } else {
                presentError(error.localizedDescription)
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    var timerStartDate: Date? { startDate }

    func stopTimer(endedAt: Date = Date()) async {
        guard let entryId = activeEntryId else { return }
        do {
            try await MoneybirdAPI.shared.stopTimer(id: entryId, endedAt: endedAt)
        } catch let error as APIError {
            if case .httpError(let code, _) = error, code == 404 {
                // Entry no longer exists in Moneybird; clean up local state silently.
            } else {
                presentError(error.localizedDescription)
            }
        } catch {
            presentError(error.localizedDescription)
        }
        clearTimerState()
        await loadRecentTimers()
    }

    func restartTimer(entry: TimeEntry) async {
        guard !isRunning else { return }
        do {
            let reopened = try await MoneybirdAPI.shared.reopenTimer(id: entry.id)
            activeEntryId = reopened.id
            startDate = parseISO8601(reopened.started_at) ?? Date()

            UserDefaults.standard.set(reopened.id, forKey: UDKey.timeEntryId)
            UserDefaults.standard.set(reopened.started_at, forKey: UDKey.startedAt)

            isRunning = true
            syncQuickActions()
            scheduleNotification(from: startDate!)
            startTicker()
            await loadRecentTimers()
        } catch let error as APIError {
            presentError(error.localizedDescription)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func selectProject(_ project: Project) {
        selectedProject = project
        UserDefaults.standard.set(project.id, forKey: UDKey.selectedProjectId)
        UserDefaults.standard.set(project.name, forKey: UDKey.selectedProjectName)
        syncQuickActions()
    }

    func selectUser(_ user: User) {
        selectedUser = user
        UserDefaults.standard.set(user.id, forKey: UDKey.selectedUserId)
    }

    func loadRecentTimers() async {
        isLoadingRecentTimers = true
        defer { isLoadingRecentTimers = false }
        do {
            recentTimers = try await MoneybirdAPI.shared.fetchRecentTimers()
        } catch let error as APIError {
            if case .missingCredentials = error { /* silently skip */ } else {
                presentError(error.localizedDescription)
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func deleteRecentTimer(id: String) async {
        do {
            try await MoneybirdAPI.shared.deleteTimeEntry(id: id)
            await loadRecentTimers()
        } catch let error as APIError {
            presentError(error.localizedDescription)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func updateRecentTimer(id: String, startedAt: Date, endedAt: Date) async {
        do {
            try await MoneybirdAPI.shared.updateTimeEntry(id: id, startedAt: startedAt, endedAt: endedAt)
            await loadRecentTimers()
        } catch let error as APIError {
            presentError(error.localizedDescription)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    var elapsedDisplay: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: - Private helpers

    private func restoreTimerIfNeeded() {
        guard let entryId = UserDefaults.standard.string(forKey: UDKey.timeEntryId),
              let startedAtString = UserDefaults.standard.string(forKey: UDKey.startedAt),
              let start = parseISO8601(startedAtString) else { return }

        activeEntryId = entryId
        startDate = start
        isRunning = true
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
        syncQuickActions()

        let elapsed = Date().timeIntervalSince(start)
        if elapsed < 8 * 3600 {
            scheduleNotification(from: start)
        }
        startTicker()
    }

    private func restoreSelectedProject() {
        guard let savedId = UserDefaults.standard.string(forKey: UDKey.selectedProjectId) else { return }
        selectedProject = projects.first { $0.id == savedId }
        syncQuickActions()
    }

    /// Werkt het Home Screen menu bij naar de huidige timer-status en het
    /// laatst gebruikte project.
    private func syncQuickActions() {
        let name = selectedProject?.name ?? UserDefaults.standard.string(forKey: UDKey.selectedProjectName)
        QuickActionCenter.shared.updateShortcuts(isRunning: isRunning, projectName: name)
    }

    private func restoreSelectedUser() {
        guard let savedId = UserDefaults.standard.string(forKey: UDKey.selectedUserId) else { return }
        selectedUser = users.first { $0.id == savedId }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, let start = self.startDate else { return }
                self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
            }
        }
    }

    private func clearTimerState() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        elapsedSeconds = 0
        startDate = nil
        activeEntryId = nil
        UserDefaults.standard.removeObject(forKey: UDKey.timeEntryId)
        UserDefaults.standard.removeObject(forKey: UDKey.startedAt)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["timer_8h_warning"])
        syncQuickActions()
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = path.status == .satisfied
                if !wasAvailable && self.isNetworkAvailable {
                    if self.projects.isEmpty || self.users.isEmpty {
                        await self.loadAll()
                    }
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    private func presentError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }

    private func scheduleNotification(from start: Date) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Timer nog actief"
            content.body = "Je timer loopt al meer dan 8 uur. Vergeten te stoppen?"
            content.sound = .default
            content.categoryIdentifier = "TIMER_WARNING"

            let elapsed = Date().timeIntervalSince(start)
            let remaining = max(1, 8 * 3600 - elapsed)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            let request = UNNotificationRequest(
                identifier: "timer_8h_warning",
                content: content,
                trigger: trigger
            )

            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ["timer_8h_warning"])
            center.add(request)
        }
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
