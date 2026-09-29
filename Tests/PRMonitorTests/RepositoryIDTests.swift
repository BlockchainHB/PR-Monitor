import Testing
@testable import PRMonitor

@Suite("Repository parsing")
struct RepositoryIDTests {
    @Test("Accepts every common way of writing a repository", arguments: [
        "apple/swift",
        "  apple/swift  ",
        "https://github.com/apple/swift",
        "https://github.com/apple/swift.git",
        "https://github.com/apple/swift/pull/42",
        "git@github.com:apple/swift.git",
    ])
    func parses(_ input: String) {
        #expect(RepositoryID(parsing: input) == RepositoryID(owner: "apple", name: "swift"))
    }

    @Test("Rejects malformed input", arguments: [
        "", "swift", "/swift", "apple/", "-apple/swift", "apple/sw ift", "https://gitlab.com/apple/swift", "apple/..",
    ])
    func rejects(_ input: String) {
        #expect(RepositoryID(parsing: input) == nil)
    }

    @Test func sortsNaturally() {
        let ids = ["acme/rocket10", "acme/rocket2", "Acme/alpha"].compactMap(RepositoryID.init(parsing:))
        #expect(ids.sorted().map(\.name) == ["alpha", "rocket2", "rocket10"])
    }
}
