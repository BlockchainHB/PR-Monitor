import Foundation

/// GitHub's OAuth device authorization flow (RFC 8628): no client secret, no redirect URI.
struct DeviceFlow: Sendable {
    struct Authorization: Hashable, Sendable {
        let userCode: String
        let deviceCode: String
        let verificationURL: URL
        let expiresAt: Date
        let interval: TimeInterval
    }

    enum Failure: Error, Equatable, LocalizedError {
        case expired
        case denied
        case misconfigured(String)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .expired: "The sign-in code expired. Start again to get a new one."
            case .denied: "Sign-in was cancelled on GitHub."
            case let .misconfigured(detail): "GitHub rejected the OAuth app configuration: \(detail)"
            case let .transport(detail): detail
            }
        }
    }

    /// `repo` is required to read checks on private repositories.
    static let scope = "repo"

    let clientID: String
    var session: URLSession = .monitor

    func start() async throws(Failure) -> Authorization {
        struct Payload: Decodable {
            let device_code: String
            let user_code: String
            let verification_uri: URL
            let expires_in: TimeInterval
            let interval: TimeInterval?
        }
        let payload: Payload = try await post("https://github.com/login/device/code", ["client_id": clientID, "scope": Self.scope])
        return Authorization(
            userCode: payload.user_code,
            deviceCode: payload.device_code,
            verificationURL: payload.verification_uri,
            expiresAt: .now.addingTimeInterval(payload.expires_in),
            interval: payload.interval ?? 5
        )
    }

    /// Polls until the user approves, denies, or the code expires. Cancelling the task stops polling.
    func token(for authorization: Authorization) async throws(Failure) -> String {
        struct Payload: Decodable {
            let access_token: String?
            let error: String?
            let error_description: String?
            let interval: TimeInterval?
        }

        var interval = authorization.interval
        while Date.now < authorization.expiresAt {
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                throw .transport("Sign-in was cancelled.")
            }
            let payload: Payload = try await post("https://github.com/login/oauth/access_token", [
                "client_id": clientID,
                "device_code": authorization.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let token = payload.access_token { return token }
            switch payload.error {
            case "authorization_pending": continue
            case "slow_down": interval = payload.interval ?? interval + 5
            case "expired_token": throw .expired
            case "access_denied": throw .denied
            default: throw .misconfigured(payload.error_description ?? payload.error ?? "unknown error")
            }
        }
        throw .expired
    }

    private func post<Payload: Decodable>(_ url: String, _ form: [String: String]) async throws(Failure) -> Payload {
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Failure.misconfigured("HTTP \(http.statusCode)")
            }
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch let failure as Failure {
            throw failure
        } catch is DecodingError {
            throw .misconfigured("Unexpected response. Check the OAuth app's client ID and that device flow is enabled.")
        } catch {
            throw .transport(error.localizedDescription)
        }
    }
}
