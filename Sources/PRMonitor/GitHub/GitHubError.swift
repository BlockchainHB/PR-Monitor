import Foundation

enum GitHubError: Error, Hashable, Sendable, LocalizedError {
    /// The token is missing, expired or revoked.
    case unauthorized
    case rateLimited(resetAt: Date?)
    case forbidden(String)
    case notFound(String)
    case offline
    case network(String)
    case server(status: Int)
    case graphQL([String])
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Your GitHub session has expired. Sign in again to resume monitoring."
        case let .rateLimited(resetAt):
            if let resetAt {
                "GitHub's rate limit was reached. Monitoring resumes \(resetAt.formatted(.relative(presentation: .named)))."
            } else {
                "GitHub's rate limit was reached. Monitoring resumes shortly."
            }
        case let .forbidden(message):
            message.isEmpty ? "GitHub denied access." : message
        case let .notFound(message):
            message
        case .offline:
            "You're offline. Monitoring resumes when your connection is back."
        case let .network(message):
            message
        case let .server(status):
            "GitHub is having trouble (HTTP \(status)). Retrying automatically."
        case let .graphQL(messages):
            messages.first ?? "GitHub returned an error."
        case let .decoding(detail):
            "GitHub sent a response PR Monitor couldn't read. \(detail)"
        }
    }

    init(_ error: URLError) {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            self = .offline
        case .userAuthenticationRequired:
            self = .unauthorized
        default:
            self = .network(error.localizedDescription)
        }
    }
}
