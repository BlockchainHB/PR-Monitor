import Foundation

/// Reuses the credentials of the GitHub CLI (`gh`), which most developers already have signed in.
enum GitHubCLI {
    /// GUI apps don't inherit the shell's PATH, so look in the usual install locations.
    private static let candidatePaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
        "\(NSHomeDirectory())/.local/bin/gh",
    ]

    static var executableURL: URL? {
        candidatePaths.lazy
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(filePath: $0) }
            .first
    }

    static var isInstalled: Bool { executableURL != nil }

    enum Failure: Error, LocalizedError {
        case notInstalled
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .notInstalled: "The GitHub CLI isn't installed."
            case .notSignedIn: "The GitHub CLI isn't signed in. Run `gh auth login` in Terminal, then try again."
            }
        }
    }

    /// Runs `gh auth token` off the main thread.
    static func token() async throws -> String {
        guard let executableURL else { throw Failure.notInstalled }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let token = String(decoding: data, as: UTF8.self).trimmed
            guard process.terminationStatus == 0, !token.isEmpty else { throw Failure.notSignedIn }
            return token
        }.value
    }
}
