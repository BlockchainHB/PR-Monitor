import AppKit
import Foundation
import Observation

/// The signed-in GitHub identity and the ways to obtain one.
@Observable
@MainActor
final class Account {
    struct Credential: Codable, Equatable, Sendable {
        enum Source: String, Codable, Sendable {
            case deviceFlow, githubCLI, personalAccessToken

            var label: String {
                switch self {
                case .deviceFlow: "Signed in with GitHub"
                case .githubCLI: "Using GitHub CLI credentials"
                case .personalAccessToken: "Using a personal access token"
                }
            }
        }

        let token: String
        let source: Source
        var login: String?
    }

    enum State: Equatable {
        case signedOut
        /// Waiting for the user to enter `userCode` on github.com.
        case authorizing(DeviceFlow.Authorization)
        case verifying
        case signedIn(Credential)
    }

    private(set) var state: State = .signedOut
    /// The most recent sign-in problem, shown inline in Settings.
    private(set) var problem: String?

    var credential: Credential? {
        if case let .signedIn(credential) = state { return credential }
        return nil
    }

    var isSignedIn: Bool { credential != nil }

    #if DEBUG
    /// Development builds keep their own credential so they never prompt for, or overwrite, the
    /// release app's keychain item (which is bound to a different code signature).
    private let keychain = Keychain(service: "PRMonitor.debug")
    #else
    private let keychain = Keychain(service: "PRMonitor")
    #endif
    private let credentialAccount = "github_credential"
    private let legacyTokenAccount = "github_token"
    private var signInTask: Task<Void, Never>?

    init() {
        if let data = keychain.read(credentialAccount),
           let credential = try? JSONDecoder().decode(Credential.self, from: data) {
            state = .signedIn(credential)
        } else if let legacy = keychain.read(legacyTokenAccount), let token = String(data: legacy, encoding: .utf8), !token.isEmpty {
            // Migrate 0.x installs, which stored the bare device-flow token. The legacy item is
            // removed on sign-out rather than here, so a downgrade keeps working.
            let credential = Credential(token: token, source: .deviceFlow)
            persist(credential)
            state = .signedIn(credential)
        }
    }

    #if DEBUG
    /// A signed-in account for previews and snapshots. Never touches the keychain.
    init(previewLogin: String) {
        state = .signedIn(Credential(token: "", source: .githubCLI, login: previewLogin))
    }

    init(previewSignedOut: Void) {}
    #endif

    // MARK: - Sign in

    func signInWithDeviceFlow(clientID: String) {
        guard !clientID.trimmed.isEmpty else {
            problem = "Device sign-in needs a GitHub OAuth app client ID. Add one under Advanced, or use the GitHub CLI or a token."
            return
        }
        begin {
            let flow = DeviceFlow(clientID: clientID.trimmed)
            let authorization = try await flow.start()
            self.state = .authorizing(authorization)
            // Put the code on the clipboard so the user can paste it straight into the browser.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(authorization.userCode, forType: .string)
            NSWorkspace.shared.open(authorization.verificationURL)
            let token = try await flow.token(for: authorization)
            try await self.complete(with: Credential(token: token, source: .deviceFlow))
        }
    }

    func signInWithGitHubCLI() {
        begin {
            self.state = .verifying
            let token = try await GitHubCLI.token()
            try await self.complete(with: Credential(token: token, source: .githubCLI))
        }
    }

    func signIn(personalAccessToken token: String) {
        let token = token.trimmed
        guard !token.isEmpty else { return }
        begin {
            self.state = .verifying
            try await self.complete(with: Credential(token: token, source: .personalAccessToken))
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        if !isSignedIn { state = .signedOut }
    }

    // MARK: - Sign out

    func signOut() {
        cancelSignIn()
        keychain.delete(credentialAccount)
        keychain.delete(legacyTokenAccount)
        state = .signedOut
        problem = nil
    }

    /// Called when GitHub rejects the stored token (revoked, expired, or scopes removed).
    func sessionExpired() {
        guard isSignedIn else { return }
        keychain.delete(credentialAccount)
        keychain.delete(legacyTokenAccount)
        state = .signedOut
        problem = GitHubError.unauthorized.errorDescription
    }

    /// Records the viewer's login the first time the monitor learns it.
    func update(login: String) {
        guard case var .signedIn(credential) = state, credential.login != login else { return }
        credential.login = login
        persist(credential)
        state = .signedIn(credential)
    }

    // MARK: - Helpers

    private func begin(_ work: @escaping @MainActor () async throws -> Void) {
        signInTask?.cancel()
        problem = nil
        signInTask = Task {
            do {
                try await work()
            } catch is CancellationError {
                // The user cancelled; nothing to report.
            } catch {
                guard !Task.isCancelled else { return }
                self.problem = error.localizedDescription
                if !self.isSignedIn { self.state = .signedOut }
            }
        }
    }

    /// Verifies the token actually works before saving it, so a typo never looks like a sign-in.
    private func complete(with credential: Credential) async throws {
        var credential = credential
        do {
            credential.login = try await GitHubClient(token: credential.token).viewerLogin()
        } catch .unauthorized {
            throw GitHubError.forbidden("GitHub didn't accept that token.")
        }
        try Task.checkCancellation()
        persist(credential)
        state = .signedIn(credential)
    }

    private func persist(_ credential: Credential) {
        if let data = try? JSONEncoder().encode(credential) {
            keychain.write(data, for: credentialAccount)
        }
    }
}
