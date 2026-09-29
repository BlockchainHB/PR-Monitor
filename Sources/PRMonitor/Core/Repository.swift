import Foundation

/// A GitHub repository coordinate (`owner/name`).
struct RepositoryID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    let owner: String
    let name: String

    init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Parses `owner/name`, `https://github.com/owner/name[.git][/…]`, or `git@github.com:owner/name.git`.
    init?(parsing input: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("git@github.com:") {
            text.removeFirst("git@github.com:".count)
        } else if let url = URL(string: text), let host = url.host(), host.hasSuffix("github.com") {
            text = url.path()
        }
        if text.hasSuffix(".git") { text.removeLast(4) }

        let parts = text.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        // Anything beyond owner/name (e.g. `/pull/12`) is ignored so pasted URLs just work.
        let owner = parts[0], name = parts[1]
        guard Self.isValidOwner(owner), Self.isValidName(name) else { return nil }
        self.init(owner: owner, name: name)
    }

    var fullName: String { "\(owner)/\(name)" }
    var description: String { fullName }
    var url: URL { URL(string: "https://github.com/\(owner)/\(name)")! }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.fullName.localizedStandardCompare(rhs.fullName) == .orderedAscending
    }

    private static func isValidOwner(_ owner: String) -> Bool {
        owner.count <= 39 && owner.wholeMatch(of: /[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/) != nil
    }

    private static func isValidName(_ name: String) -> Bool {
        name.count <= 100 && name != "." && name != ".." && name.wholeMatch(of: /[A-Za-z0-9._-]+/) != nil
    }
}

/// A repository the user has chosen to monitor.
struct TrackedRepository: Identifiable, Hashable, Codable, Sendable {
    var id: RepositoryID
    var isEnabled: Bool = true
}
