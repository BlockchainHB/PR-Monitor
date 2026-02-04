import Foundation
import AppKit

struct DeviceFlowState: Hashable {
    var userCode: String
    var deviceCode: String
    var verificationURL: URL
    var expiresAt: Date
    var intervalSeconds: Int
}

@MainActor
final class AuthStore: ObservableObject {
    @Published var token: String?
    @Published var deviceFlow: DeviceFlowState?
    @Published var statusMessage: String?
    @Published var isSigningIn: Bool = false

    private let service = "PRMonitor"
    private let account = "github_token"
    private let authService = GitHubAuthService()

    init() {
        token = Keychain.load(service: service, account: account)
    }

    var isSignedIn: Bool { token != nil }

    func signIn(clientId: String) {
        guard !clientId.isEmpty else {
            statusMessage = "Add a GitHub OAuth client ID in Settings."
            return
        }
        statusMessage = nil
        isSigningIn = true
        Task {
            do {
                let flow = try await authService.startDeviceFlow(clientId: clientId)
                deviceFlow = flow
                NSWorkspace.shared.open(flow.verificationURL)
                let tokenValue = try await authService.pollForToken(clientId: clientId, deviceCode: flow.deviceCode, intervalSeconds: flow.intervalSeconds, expiresAt: flow.expiresAt)
                token = tokenValue
                Keychain.save(service: service, account: account, value: tokenValue)
                statusMessage = "Connected."
                deviceFlow = nil
            } catch {
                statusMessage = "Sign-in failed: \(error.localizedDescription)"
            }
            isSigningIn = false
        }
    }

    func signOut() {
        token = nil
        deviceFlow = nil
        Keychain.delete(service: service, account: account)
    }
}
