import Foundation

enum GitHubClientError: Error, LocalizedError {
    case missingToken
    case invalidResponse
    case rateLimited(reset: Date?)
    case httpError(status: Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Missing GitHub token."
        case .invalidResponse:
            return "Unexpected GitHub response."
        case .rateLimited(let reset):
            if let reset {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                let relative = formatter.localizedString(for: reset, relativeTo: Date())
                return "GitHub API rate limit exceeded. Try again \(relative)."
            }
            return "GitHub API rate limit exceeded. Try again later."
        case .httpError(let status):
            return "GitHub API returned HTTP \(status)."
        }
    }
}

final class GitHubClient {
    private let session: URLSession
    private let tokenProvider: () -> String?
    private let decoder: JSONDecoder
    private let pathSegmentAllowedCharacters: CharacterSet

    init(session: URLSession = .shared, tokenProvider: @escaping () -> String?) {
        self.session = session
        self.tokenProvider = tokenProvider
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        self.pathSegmentAllowedCharacters = allowed
    }

    func fetchOpenPullRequests(repo: RepoConfig) async throws -> [PullRequestDTO] {
        var page = 1
        var pulls: [PullRequestDTO] = []
        while true {
            let url = try apiURL(
                pathSegments: ["repos", repo.owner, repo.name, "pulls"],
                queryItems: [
                    URLQueryItem(name: "state", value: "open"),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ]
            )
            let request = try makeRequest(url: url)
            let (data, response) = try await session.data(for: request)
            try validate(response: response)
            let batch = try decoder.decode([PullRequestDTO].self, from: data)
            pulls.append(contentsOf: batch)
            if batch.count < 100 { break }
            page += 1
        }
        return pulls
    }

    func fetchCheckRuns(owner: String, repo: String, sha: String) async throws -> [CheckRunDTO] {
        var page = 1
        var runs: [CheckRunDTO] = []
        var totalCount: Int?
        while true {
            let url = try apiURL(
                pathSegments: ["repos", owner, repo, "commits", sha, "check-runs"],
                queryItems: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "filter", value: "latest")
                ]
            )
            let request = try makeRequest(url: url)
            let (data, response) = try await session.data(for: request)
            try validate(response: response)
            let payload = try decoder.decode(CheckRunsResponse.self, from: data)
            totalCount = payload.totalCount
            runs.append(contentsOf: payload.checkRuns)
            if payload.checkRuns.count < 100 { break }
            if let totalCount, runs.count >= totalCount { break }
            page += 1
        }
        return runs
    }

    func fetchReviewComments(owner: String, repo: String, prNumber: Int) async throws -> [PRComment] {
        var page = 1
        var comments: [PRComment] = []
        while true {
            let url = try apiURL(
                pathSegments: ["repos", owner, repo, "pulls", String(prNumber), "comments"],
                queryItems: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ]
            )
            let request = try makeRequest(url: url)
            let (data, response) = try await session.data(for: request)
            try validate(response: response)
            let batch = try decoder.decode([ReviewCommentDTO].self, from: data)
            comments.append(contentsOf: batch.map { PRComment(author: $0.user.login, createdAt: $0.createdAt) })
            if batch.count < 100 { break }
            page += 1
        }
        return comments
    }

    func fetchIssueComments(owner: String, repo: String, prNumber: Int) async throws -> [PRComment] {
        var page = 1
        var comments: [PRComment] = []
        while true {
            let url = try apiURL(
                pathSegments: ["repos", owner, repo, "issues", String(prNumber), "comments"],
                queryItems: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ]
            )
            let request = try makeRequest(url: url)
            let (data, response) = try await session.data(for: request)
            try validate(response: response)
            let batch = try decoder.decode([IssueCommentDTO].self, from: data)
            comments.append(contentsOf: batch.map { PRComment(author: $0.user.login, createdAt: $0.createdAt) })
            if batch.count < 100 { break }
            page += 1
        }
        return comments
    }

    func fetchPullRequestReviews(owner: String, repo: String, prNumber: Int) async throws -> [PRComment] {
        var page = 1
        var comments: [PRComment] = []
        while true {
            let url = try apiURL(
                pathSegments: ["repos", owner, repo, "pulls", String(prNumber), "reviews"],
                queryItems: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ]
            )
            let request = try makeRequest(url: url)
            let (data, response) = try await session.data(for: request)
            try validate(response: response)
            let batch = try decoder.decode([PullRequestReviewDTO].self, from: data)
            comments.append(contentsOf: batch.compactMap { review in
                guard let submittedAt = review.submittedAt else { return nil }
                let body = review.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !body.isEmpty else { return nil }
                return PRComment(author: review.user.login, createdAt: submittedAt)
            })
            if batch.count < 100 { break }
            page += 1
        }
        return comments
    }

    func fetchAllPRComments(owner: String, repo: String, prNumber: Int) async throws -> [PRComment] {
        async let reviewComments = fetchReviewComments(owner: owner, repo: repo, prNumber: prNumber)
        async let issueComments = fetchIssueComments(owner: owner, repo: repo, prNumber: prNumber)
        async let reviews = fetchPullRequestReviews(owner: owner, repo: repo, prNumber: prNumber)
        let resolvedReviewComments = try await reviewComments
        let resolvedIssueComments = try await issueComments
        let resolvedReviews = try await reviews
        return resolvedReviewComments + resolvedIssueComments + resolvedReviews
    }

    func fetchViewerLogin() async throws -> String {
        let url = try apiURL(pathSegments: ["user"])
        let request = try makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        let payload = try decoder.decode(ViewerDTO.self, from: data)
        return payload.login
    }

    func fetchViewerRepos(page: Int) async throws -> [RepoDTO] {
        let url = try apiURL(
            pathSegments: ["user", "repos"],
            queryItems: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
                URLQueryItem(name: "sort", value: "updated")
            ]
        )
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
        request.setValue("PRMonitor", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func apiURL(pathSegments: [String], queryItems: [URLQueryItem] = []) throws -> URL {
        let encodedSegments = pathSegments.compactMap {
            $0.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowedCharacters)
        }
        guard encodedSegments.count == pathSegments.count else {
            throw GitHubClientError.invalidResponse
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.percentEncodedPath = "/" + encodedSegments.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw GitHubClientError.invalidResponse
        }
        return url
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GitHubClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 403 || http.statusCode == 429 {
                let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining")
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset")

                let resetDate: Date? = {
                    if let retryAfter, let seconds = TimeInterval(retryAfter) {
                        return Date().addingTimeInterval(seconds)
                    }
                    if let reset, let timestamp = TimeInterval(reset) {
                        return Date(timeIntervalSince1970: timestamp)
                    }
                    return nil
                }()

                if remaining == "0" || http.statusCode == 429 {
                    throw GitHubClientError.rateLimited(reset: resetDate)
                }
            }
            throw GitHubClientError.httpError(status: http.statusCode)
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
    var totalCount: Int

    enum CodingKeys: String, CodingKey {
        case checkRuns = "check_runs"
        case totalCount = "total_count"
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
    var createdAt: Date?
    var startedAt: Date?
    var completedAt: Date?
    var app: App?

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case conclusion
        case createdAt = "created_at"
        case startedAt = "started_at"
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
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case createdAt = "created_at"
    }
}

struct IssueCommentDTO: Decodable {
    struct User: Decodable {
        var login: String
    }

    var id: Int
    var user: User
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case createdAt = "created_at"
    }
}

struct PullRequestReviewDTO: Decodable {
    struct User: Decodable {
        var login: String
    }

    var id: Int
    var user: User
    var submittedAt: Date?
    var body: String?

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case submittedAt = "submitted_at"
        case body
    }
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
