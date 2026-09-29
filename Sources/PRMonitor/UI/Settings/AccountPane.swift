import SwiftUI

struct AccountPane: View {
    @Environment(Account.self) private var account
    @Environment(AppSettings.self) private var settings
    @State private var token = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            switch account.state {
            case let .signedIn(credential):
                signedIn(credential)
            case let .authorizing(authorization):
                authorizing(authorization)
            case .verifying:
                Section {
                    HStack(spacing: 12) {
                        BoneCircle(size: 44)
                        VStack(alignment: .leading, spacing: 7) {
                            Bone(width: 120, height: 11)
                            Bone(width: 170, height: 8)
                        }
                    }
                    .padding(.vertical, 2)
                    .skeletonPulse()
                } header: {
                    Text("GitHub")
                } footer: {
                    Text("Verifying with GitHub…")
                }
            case .signedOut:
                signInOptions
            }

            Section {
                TextField("OAuth app client ID", text: $settings.oauthClientIDOverride, prompt: Text(bundledClientIDPrompt))
                    .autocorrectionDisabled()
            } header: {
                Text("Advanced")
            } footer: {
                Text("Only needed for “Sign in with GitHub” when you build PR Monitor yourself. Create an OAuth app with device flow enabled at github.com/settings/developers.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Signed in

    private func signedIn(_ credential: Account.Credential) -> some View {
        Section {
            HStack(spacing: 12) {
                Avatar(login: credential.login, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(credential.login ?? "GitHub account")
                        .font(.headline)
                    Text(credential.source.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sign Out") { account.signOut() }
            }
            .padding(.vertical, 2)
        } header: {
            Text("GitHub")
        } footer: {
            Text("Your token is stored in your login keychain and is only ever sent to api.github.com.")
        }
    }

    // MARK: - Device flow in progress

    private func authorizing(_ authorization: DeviceFlow.Authorization) -> some View {
        Section {
            VStack(spacing: 10) {
                Text("Enter this code on GitHub")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(authorization.userCode)
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .tracking(2)
                    .textSelection(.enabled)
                    .accessibilityLabel("Code: \(authorization.userCode.map(String.init).joined(separator: " "))")
                Text("It's been copied to your clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel", role: .cancel) { account.cancelSignIn() }
                    Button("Copy Code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(authorization.userCode, forType: .string)
                    }
                    Button("Open GitHub") { NSWorkspace.shared.open(authorization.verificationURL) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to approve…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } header: {
            Text("Sign in with GitHub")
        }
    }

    // MARK: - Signed out

    @ViewBuilder
    private var signInOptions: some View {
        Section {
            option(
                title: "GitHub CLI",
                detail: GitHubCLI.isInstalled
                    ? "Use the account you're signed in to with gh."
                    : "Install with `brew install gh`, then run `gh auth login`.",
                button: "Use GitHub CLI",
                isEnabled: GitHubCLI.isInstalled
            ) { account.signInWithGitHubCLI() }

            option(
                title: "Sign in with GitHub",
                detail: settings.oauthClientID.isEmpty
                    ? "Requires an OAuth app client ID (see Advanced)."
                    : "Approve PR Monitor in your browser with a one-time code.",
                button: "Sign In…",
                isEnabled: !settings.oauthClientID.isEmpty
            ) { account.signInWithDeviceFlow(clientID: settings.oauthClientID) }

            VStack(alignment: .leading, spacing: 8) {
                Text("Personal access token")
                Text("A classic token with the repo scope, or a fine-grained token with read access to pull requests, checks and commit statuses.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    SecureField("Token", text: $token, prompt: Text("ghp_… or github_pat_…"))
                        .labelsHidden()
                        .onSubmit(useToken)
                    Button("Use Token", action: useToken)
                        .disabled(token.trimmed.isEmpty)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Connect to GitHub")
        } footer: {
            if let problem = account.problem {
                Text(problem).foregroundStyle(.red)
            }
        }
    }

    private func option(title: String, detail: LocalizedStringKey, button: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(button, action: action)
                .disabled(!isEnabled)
        }
        .padding(.vertical, 2)
    }

    private func useToken() {
        account.signIn(personalAccessToken: token)
        token = ""
    }

    private var bundledClientIDPrompt: String {
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String)?.trimmed ?? ""
        return bundled.isEmpty ? "Not set" : "Using built-in \(bundled.prefix(8))…"
    }
}
