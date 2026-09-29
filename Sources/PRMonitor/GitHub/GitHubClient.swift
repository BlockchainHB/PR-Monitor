import Foundation

/// A minimal GitHub GraphQL client. It knows about transport concerns only — auth, rate limits,
/// and error mapping — and nothing about pull requests.
struct GitHubClient: Sendable {
    static let endpoint = URL(string: "https://api.github.com/graphql")!

    let token: String
    var session: URLSession = .monitor

    struct Response<Payload: Decodable & Sendable>: Sendable {
        let data: Payload?
        /// Errors scoped to part of the query (e.g. one repository alias), alongside partial data.
        let errors: [GraphQLError]
    }

    func query<Payload: Decodable & Sendable>(
        _ document: String,
        variables: [String: GraphQLVariable] = [:],
        as payload: Payload.Type = Payload.self
    ) async throws(GitHubError) -> Response<Payload> {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            request.httpBody = try JSONEncoder().encode(Body(query: document, variables: variables))
        } catch {
            throw .decoding("Couldn't encode the request.")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw GitHubError(error)
        } catch {
            throw .network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw .network("No response from GitHub.") }
        try Self.validate(http, body: data)

        let envelope: Envelope<Payload>
        do {
            envelope = try Self.decoder.decode(Envelope<Payload>.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }

        let errors = envelope.errors ?? []
        if errors.contains(where: { $0.type == "RATE_LIMITED" }) {
            throw .rateLimited(resetAt: Self.rateLimitReset(http))
        }
        guard envelope.data != nil else {
            throw .graphQL(errors.map(\.message))
        }
        return Response(data: envelope.data, errors: errors)
    }

    // MARK: - HTTP validation

    private static func validate(_ http: HTTPURLResponse, body: Data) throws(GitHubError) {
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw .unauthorized
        case 403, 429:
            // Primary limit: remaining hits zero. Secondary limit: a Retry-After header.
            let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining")
            if remaining == "0" || http.value(forHTTPHeaderField: "retry-after") != nil || http.statusCode == 429 {
                throw .rateLimited(resetAt: rateLimitReset(http))
            }
            throw .forbidden(message(in: body) ?? "")
        case 500...:
            throw .server(status: http.statusCode)
        default:
            throw .network(message(in: body) ?? "GitHub returned HTTP \(http.statusCode).")
        }
    }

    private static func rateLimitReset(_ http: HTTPURLResponse) -> Date? {
        if let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init) {
            return .now.addingTimeInterval(retryAfter)
        }
        if let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: reset)
        }
        return nil
    }

    private static func message(in body: Data) -> String? {
        struct Message: Decodable { let message: String }
        return try? JSONDecoder().decode(Message.self, from: body).message
    }

    // MARK: - Coding

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "PRMonitor/\(version)"
    }()

    private struct Body: Encodable {
        let query: String
        let variables: [String: GraphQLVariable]
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let data: Payload?
        let errors: [GraphQLError]?
    }
}

struct GraphQLError: Decodable, Sendable, Hashable {
    let type: String?
    let message: String
    let path: [PathComponent]?

    /// The top-level field (alias) this error belongs to, e.g. `r3`.
    var rootField: String? {
        if case let .key(key) = path?.first { return key }
        return nil
    }

    enum PathComponent: Decodable, Sendable, Hashable {
        case key(String)
        case index(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let index = try? container.decode(Int.self) {
                self = .index(index)
            } else {
                self = .key(try container.decode(String.self))
            }
        }
    }
}

enum GraphQLVariable: Encodable, Sendable, Hashable {
    case string(String)
    case strings([String])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .strings(values): try container.encode(values)
        case .null: try container.encodeNil()
        }
    }
}

extension URLSession {
    /// Short timeouts and no caching: a monitor wants fresh data or a fast failure it can retry.
    static let monitor: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["X-Github-Next-Global-ID": "1"]
        return URLSession(configuration: configuration)
    }()
}
