import Foundation

/// A repository the signed-in user can access, for the repository picker.
struct RemoteRepository: Identifiable, Hashable, Sendable {
    let id: RepositoryID
    let isPrivate: Bool
    let description: String?
    let pushedAt: Date?
}

extension GitHubClient {
    func viewerLogin() async throws(GitHubError) -> String {
        struct Payload: Decodable, Sendable {
            struct Viewer: Decodable, Sendable { let login: String }
            let viewer: Viewer
        }
        let response = try await query("query { viewer { login } }", as: Payload.self)
        guard let login = response.data?.viewer.login else { throw .graphQL(["Couldn't read your GitHub account."]) }
        return login
    }

    /// Repositories the viewer owns, collaborates on, or can see through an organization,
    /// most recently pushed first. Capped so a huge org can't stall the picker.
    func viewerRepositories(limit: Int = 500) async throws(GitHubError) -> [RemoteRepository] {
        struct Payload: Decodable, Sendable {
            struct Viewer: Decodable, Sendable { let repositories: Page }
            struct Page: Decodable, Sendable {
                struct PageInfo: Decodable, Sendable { let hasNextPage: Bool; let endCursor: String? }
                let pageInfo: PageInfo
                let nodes: [Node]
            }
            struct Node: Decodable, Sendable {
                let nameWithOwner: String
                let isPrivate: Bool
                let description: String?
                let pushedAt: Date?
            }
            let viewer: Viewer
        }

        let document = """
        query PRMonitorRepositories($cursor: String) {
          viewer {
            repositories(first: 100, after: $cursor, isArchived: false,
                         affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER],
                         ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER],
                         orderBy: {field: PUSHED_AT, direction: DESC}) {
              pageInfo { hasNextPage endCursor }
              nodes { nameWithOwner isPrivate description pushedAt }
            }
          }
        }
        """

        var cursor: String?
        var results: [RemoteRepository] = []
        repeat {
            let response = try await query(document, variables: ["cursor": cursor.map(GraphQLVariable.string) ?? .null], as: Payload.self)
            guard let page = response.data?.viewer.repositories else { break }
            results += page.nodes.compactMap { node in
                RepositoryID(parsing: node.nameWithOwner).map {
                    RemoteRepository(id: $0, isPrivate: node.isPrivate, description: node.description, pushedAt: node.pushedAt)
                }
            }
            cursor = page.pageInfo.hasNextPage ? page.pageInfo.endCursor : nil
        } while cursor != nil && results.count < limit
        return results
    }
}
