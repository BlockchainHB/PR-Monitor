import Foundation

/// Something that reports on a pull request: a CI system, a deploy integration, or an AI reviewer.
///
/// An agent is matched against a PR by two independent keys. Either may be empty, but not both.
/// - `checkPattern` matches check runs and commit statuses (by name, app, or creator).
/// - `login` matches the bot account that requests reviews, leaves review threads, or comments.
struct Agent: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var checkPattern: String = ""
    var login: String = ""

    var isValid: Bool {
        !name.trimmed.isEmpty && !(checkPattern.trimmed.isEmpty && login.trimmed.isEmpty)
    }
}

enum AgentMode: String, Codable, Sendable, CaseIterable {
    /// Every check and review bot that reports on a PR becomes an agent. Zero configuration.
    case automatic
    /// Only the agents the user configured are tracked; everything else is ignored.
    case custom
}

extension Agent {
    /// Well-known integrations. Logins are the GraphQL bot logins (without the `[bot]` suffix).
    static let presets: [Agent] = [
        Agent(name: "CodeRabbit", checkPattern: "coderabbit", login: "coderabbitai"),
        Agent(name: "Copilot", login: "copilot-pull-request-reviewer"),
        Agent(name: "Cursor Bugbot", checkPattern: "cursor", login: "cursor"),
        Agent(name: "Devin", checkPattern: "devin", login: "devin-ai-integration"),
        Agent(name: "Codex", login: "chatgpt-codex-connector"),
        Agent(name: "Gemini Code Assist", login: "gemini-code-assist"),
        Agent(name: "Graphite", checkPattern: "graphite", login: "graphite-app"),
        Agent(name: "Greptile", checkPattern: "greptile", login: "greptile-apps"),
        Agent(name: "Sourcery", login: "sourcery-ai"),
        Agent(name: "GitHub Actions", checkPattern: "github-actions"),
        Agent(name: "Vercel", checkPattern: "vercel", login: "vercel"),
        Agent(name: "Netlify", checkPattern: "netlify", login: "netlify"),
    ]

    /// A friendly name for a bot login or app slug, if it belongs to a known integration.
    static func presetName(forKey key: String) -> String? {
        let key = Identity.normalize(key)
        return presets.first { Identity.normalize($0.login) == key || Identity.normalize($0.checkPattern) == key }?.name
    }
}

/// Normalizes GitHub identities so that `cursor[bot]` (REST), `cursor` (GraphQL) and `Cursor` compare equal.
enum Identity {
    static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacing("[bot]", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
