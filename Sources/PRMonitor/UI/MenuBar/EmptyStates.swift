import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var action: (title: String, tab: AppRouter.SettingsTab)?

    @Environment(AppRouter.self) private var router
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.title) { router.showSettings(action.tab, using: openSettings) }
                    .controlSize(.regular)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 28)
    }
}

/// First-run onboarding. If the GitHub CLI is signed in, connecting is a single click.
struct ConnectGitHubView: View {
    @Environment(Account.self) private var account
    @Environment(AppRouter.self) private var router
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// First-run is rare, so its content arrives in a short stagger: mark, headline, copy, actions.
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 6) {
            PullRequestMark()
                .fill(.white)
                .frame(width: 24, height: 24)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.accentColor.gradient))
                .padding(.bottom, 6)
                .staggeredEntrance(0, isVisible: hasAppeared, reduceMotion: reduceMotion)
            Text("Connect to GitHub")
                .font(.title3.weight(.semibold))
                .staggeredEntrance(1, isVisible: hasAppeared, reduceMotion: reduceMotion)
            Text("PR Monitor watches the checks and AI reviews on your pull requests, and tells you when they're ready for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .staggeredEntrance(2, isVisible: hasAppeared, reduceMotion: reduceMotion)

            VStack(spacing: 8) {
                if GitHubCLI.isInstalled {
                    Button {
                        account.signInWithGitHubCLI()
                    } label: {
                        Text(account.state == .verifying ? "Connecting…" : "Continue with GitHub CLI")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(account.state == .verifying)

                    Button("Other Sign-In Options…") { router.showSettings(.account, using: openSettings) }
                        .buttonStyle(.link)
                        .font(.subheadline)
                } else {
                    Button {
                        router.showSettings(.account, using: openSettings)
                    } label: {
                        Text("Sign In…").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            .padding(.top, 12)
            .staggeredEntrance(3, isVisible: hasAppeared, reduceMotion: reduceMotion)

            if let problem = account.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .onAppear { hasAppeared = true }
    }
}

private extension View {
    /// Opacity, a 4pt blur and an 8pt rise, staggered 80ms per chunk. Opacity only with Reduce Motion.
    func staggeredEntrance(_ index: Int, isVisible: Bool, reduceMotion: Bool) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible || reduceMotion ? 0 : 4)
            .offset(y: isVisible || reduceMotion ? 0 : 8)
            .animation(.smooth(duration: 0.4).delay(Double(index) * 0.08), value: isVisible)
    }
}
