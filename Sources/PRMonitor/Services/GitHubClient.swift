import Foundation

enum GitHubClientError: Error, LocalizedError {
    case missingToken
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Missing GitHub token."
        case .invalidResponse:
            return "Unexpected GitHub response."
        }
    }
}

final class GitHubClient {
    private let session: URLSession
    private let tokenProvider: () -> String?
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, tokenProvider: @escaping () -> String?) {
        self.session = session
        self.tokenProvider = tokenProvider
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func fetchOpenPullRequests(repo: RepoConfig) async throws -> [PullRequestDTO] {
        let url = URL(string: "https://api.github.com/repos/\(repo.owner)/\(repo.name)/pulls?state=open&per_page=50")!
        var request = try makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try decoder.decode([PullRequestDTO].self, from: data)
    }

    func fetchCheckRuns(owner: String, repo: String, sha: String) async throws -> [CheckRunDTO] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/commits/\(sha)/check-runs?per_page=100")!
        let request = try makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        let payload = try decoder.decode(CheckRunsResponse.self, from: data)
        return payload.checkRuns
    }

    func fetchReviewComments(owner: String, repo: String, prNumber: Int) async throws -> [ReviewCommentDTO] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(prNumber)/comments?per_page=100")!
        let request = try makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try decoder.decode([ReviewCommentDTO].self, from: data)
    }

    func fetchViewerLogin() async throws -> String {
        let url = URL(string: "https://api.github.com/user")!
        let request = try makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        let payload = try decoder.decode(ViewerDTO.self, from: data)
        return payload.login
    }

    func fetchViewerRepos(page: Int) async throws -> [RepoDTO] {
        let url = URL(string: "https://api.github.com/user/repos?per_page=100&page=\(page)&affiliation=owner,collaborator,organization_member&sort=updated")!
        let request = try makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try decoder.decode([RepoDTO].self, from: data)
    }

    func fetchAllViewerRepos() async throws -> [RepoDTO] {
        var page = 1
        var repos: [RepoDTO] = []
        while true {
            let batch = try await fetchViewerRepos(page: page)
            if batch.isEmpty { break }
            repos.append(contentsOf: batch)
            if batch.count < 100 { break }
            page += 1
        }
        return repos
    }

    private func makeRequest(url: URL) throws -> URLRequest {
        guard let token = tokenProvider() else {
            throw GitHubClientError.missingToken
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GitHubClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw GitHubClientError.invalidResponse
        }
    }
}

struct PullRequestDTO: Decodable {
    struct User: Decodable {
        var login: String
    }
    struct Head: Decodable {
        var sha: String
    }

    var number: Int
    var title: String
    var user: User
    var updatedAt: Date
    var htmlURL: String
    var head: Head

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case user
        case updatedAt = "updated_at"
        case htmlURL = "html_url"
        case head
    }
}

struct CheckRunsResponse: Decodable {
    var checkRuns: [CheckRunDTO]

    enum CodingKeys: String, CodingKey {
        case checkRuns = "check_runs"
    }
}

struct CheckRunDTO: Decodable {
    struct App: Decodable {
        var name: String?
        var slug: String?
    }

    var name: String
    var status: String
    var conclusion: String?
    var completedAt: Date?
    var app: App?

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case conclusion
        case completedAt = "completed_at"
        case app
    }
}

struct ReviewCommentDTO: Decodable {
    struct User: Decodable {
        var login: String
    }

    var id: Int
    var user: User
}

struct ViewerDTO: Decodable {
    var login: String
}

struct RepoDTO: Decodable, Identifiable, Hashable {
    struct Owner: Decodable, Hashable {
        var login: String
    }

    var name: String
    var fullName: String
    var owner: Owner
    var isPrivate: Bool

    var id: String { fullName }

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case owner
        case isPrivate = "private"
    }
}
