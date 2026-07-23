import Foundation

struct User: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct Project: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let state: String?

    var isActive: Bool { state == "active" }
}

struct TimeEntry: Codable, Identifiable {
    let id: String
    let started_at: String
    let ended_at: String?
    let description: String
    let project_id: String?
    let user_id: String?
    // Nested objects returned by the API — used for display without extra lookups
    let project: NestedProject?
    let user: NestedUser?
}

struct NestedProject: Codable {
    let id: String
    let name: String
}

struct NestedUser: Codable {
    let id: String
    let name: String
}
