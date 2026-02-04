import Foundation

enum GitHubAuthError: Error, LocalizedError {
    case invalidResponse
    case expired
    case accessDenied
    case slowDown

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from GitHub."
        case .expired:
            return "Device code expired."
        case .accessDenied:
            return "Access denied."
        case .slowDown:
            return "GitHub asked to slow down polling."
        }
    }
}

final class GitHubAuthService {
    private let session = URLSession.shared

    func startDeviceFlow(clientId: String) async throws -> DeviceFlowState {
        guard let url = URL(string: "https://github.com/login/device/code") else {
            throw GitHubAuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = "client_id=\(clientId)&scope=repo"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await session.data(for: request)
        let payload = try parseFormEncoded(data)
        guard
            let deviceCode = payload["device_code"],
            let userCode = payload["user_code"],
            let verificationURI = payload["verification_uri"],
            let expiresIn = payload["expires_in"],
            let interval = payload["interval"],
            let verificationURL = URL(string: verificationURI),
            let expiresSeconds = Double(expiresIn),
            let intervalSeconds = Int(interval)
        else {
            throw GitHubAuthError.invalidResponse
        }

        return DeviceFlowState(
            userCode: userCode,
            deviceCode: deviceCode,
            verificationURL: verificationURL,
            expiresAt: Date().addingTimeInterval(expiresSeconds),
            intervalSeconds: intervalSeconds
        )
    }

    func pollForToken(clientId: String, deviceCode: String, intervalSeconds: Int, expiresAt: Date) async throws -> String {
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
            throw GitHubAuthError.invalidResponse
        }

        var nextInterval = intervalSeconds

        while Date() < expiresAt {
            try await Task.sleep(nanoseconds: UInt64(nextInterval) * 1_000_000_000)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            let body = "client_id=\(clientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            request.httpBody = body.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let (data, _) = try await session.data(for: request)
            let payload = try parseFormEncoded(data)

            if let token = payload["access_token"] {
                return token
            }

            if let error = payload["error"] {
                switch error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    nextInterval += 5
                    continue
                case "access_denied":
                    throw GitHubAuthError.accessDenied
                case "expired_token":
                    throw GitHubAuthError.expired
                default:
                    throw GitHubAuthError.invalidResponse
                }
            }
        }

        throw GitHubAuthError.expired
    }

    private func parseFormEncoded(_ data: Data) throws -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw GitHubAuthError.invalidResponse
        }
        var result: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            result[key] = value.removingPercentEncoding ?? value
        }
        return result
    }
}
