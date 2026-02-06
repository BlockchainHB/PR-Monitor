import XCTest
@testable import PRMonitor

final class PRMonitorSmokeTests: XCTestCase {
    func testRepoConfigFullName() {
        let repo = RepoConfig(owner: "apple", name: "swift", isEnabled: true)
        XCTAssertEqual(repo.id, "apple/swift")
        XCTAssertEqual(repo.fullName, "apple/swift")
    }

    func testAgentRunStatusRawValuesStable() {
        XCTAssertEqual(AgentRunStatus.running.rawValue, "running")
        XCTAssertEqual(AgentRunStatus.failed.rawValue, "failed")
        XCTAssertEqual(AgentRunStatus.done.rawValue, "done")
    }
}
