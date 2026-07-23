import Foundation

enum APIError: LocalizedError {
    case missingCredentials
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "API-token of administratie-ID ontbreekt. Ga naar Instellingen."
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .decodingError(let error):
            return "Decodering mislukt: \(error.localizedDescription)"
        case .networkError(let error):
            return "Netwerkfout: \(error.localizedDescription)"
        }
    }
}

actor MoneybirdAPI {
    static let shared = MoneybirdAPI()

    private func credentials() throws -> (token: String, adminId: String) {
        guard let token = KeychainHelper.load(for: .apiToken), !token.isEmpty,
              let adminId = KeychainHelper.load(for: .administrationId), !adminId.isEmpty else {
            throw APIError.missingCredentials
        }
        return (token, adminId)
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) throws -> URLRequest {
        let (token, adminId) = try credentials()
        let urlString = "https://moneybird.com/api/v2/\(adminId)/\(path)"
        guard let url = URL(string: urlString) else {
            throw APIError.httpError(statusCode: 0, body: "Ongeldige URL: \(urlString)")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.httpError(statusCode: 0, body: "Geen HTTP-response ontvangen")
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "(geen body)"
                throw APIError.httpError(statusCode: http.statusCode, body: body)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    /// Validates token + administrationId by making a lightweight API call.
    /// Throws APIError with a Dutch message tailored to the HTTP status code.
    /// Does NOT read from or write to Keychain.
    func validateCredentials(token: String, administrationId: String) async throws {
        let trimToken = token.trimmingCharacters(in: .whitespaces)
        let trimAdminId = administrationId.trimmingCharacters(in: .whitespaces)

        guard !trimToken.isEmpty, !trimAdminId.isEmpty else {
            throw APIError.missingCredentials
        }
        guard trimAdminId.allSatisfy(\.isNumber) else {
            throw APIError.httpError(statusCode: 0, body: "Het administratie-ID mag alleen cijfers bevatten.")
        }

        let urlString = "https://moneybird.com/api/v2/\(trimAdminId)/projects?per_page=1"
        guard let url = URL(string: urlString) else {
            throw APIError.httpError(statusCode: 0, body: "Ongeldige URL. Controleer het administratie-ID.")
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(trimToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.httpError(statusCode: 0, body: "Geen HTTP-response ontvangen.")
            }
            switch http.statusCode {
            case 200...299:
                return
            case 401:
                throw APIError.httpError(
                    statusCode: 401,
                    body: "Ongeldig API-token. Controleer het token in Moneybird onder Instellingen \u{2192} API."
                )
            case 403:
                throw APIError.httpError(
                    statusCode: 403,
                    body: "Dit token heeft geen toegang tot de opgegeven administratie."
                )
            case 404:
                throw APIError.httpError(
                    statusCode: 404,
                    body: "Administratie-ID niet gevonden. Controleer de URL in Moneybird."
                )
            default:
                let body = String(data: data, encoding: .utf8) ?? "(geen body)"
                throw APIError.httpError(statusCode: http.statusCode, body: body)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    func fetchRecentTimers() async throws -> [TimeEntry] {
        let request = try makeRequest(path: "time_entries?per_page=5&filter=include_active%3Atrue")
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode([TimeEntry].self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchRunningTimers() async throws -> [TimeEntry] {
        let request = try makeRequest(path: "time_entries?per_page=100")
        let data = try await perform(request)
        do {
            let all = try JSONDecoder().decode([TimeEntry].self, from: data)
            return all.filter { $0.ended_at == nil }
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchUsers() async throws -> [User] {
        let request = try makeRequest(path: "users")
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode([User].self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchProjects() async throws -> [Project] {
        let request = try makeRequest(path: "projects?per_page=100")
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode([Project].self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func startTimer(projectId: String, userId: String) async throws -> TimeEntry {
        let startedAt = iso8601String(from: Date())
        let payload: [String: Any] = [
            "time_entry": [
                "project_id": projectId,
                "user_id": userId,
                "description": "Werken",
                "started_at": startedAt,
                "billable": true
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "time_entries", method: "POST", body: body)
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(TimeEntry.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func reopenTimer(id: String) async throws -> TimeEntry {
        let request = try makeRequest(path: "time_entries/\(id)/resume", method: "PATCH")
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(TimeEntry.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func updateTimeEntry(id: String, startedAt: Date, endedAt: Date) async throws {
        let payload: [String: Any] = [
            "time_entry": [
                "started_at": iso8601String(from: startedAt),
                "ended_at":   iso8601String(from: endedAt)
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "time_entries/\(id)", method: "PATCH", body: body)
        _ = try await perform(request)
    }

    func deleteTimeEntry(id: String) async throws {
        let request = try makeRequest(path: "time_entries/\(id)", method: "DELETE")
        _ = try await perform(request)
    }

    func stopTimer(id: String, endedAt: Date = Date()) async throws {
        let endedAt = iso8601String(from: endedAt)
        let payload: [String: Any] = [
            "time_entry": ["ended_at": endedAt]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "time_entries/\(id)", method: "PATCH", body: body)
        _ = try await perform(request)
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
