import Foundation

/// Unauthenticated GitHub Releases REST client (60 req/hr/IP is plenty for a
/// once-a-day update check). No token, no Sparkle, no extra dependency — the
/// "feed" is simply the repo's Releases (matches the L-K-M family).
struct GitHubReleaseClient {
    let owner: String
    let repo: String
    var session: URLSession = .shared

    enum ClientError: LocalizedError {
        case http(Int)
        case noRelease

        var errorDescription: String? {
            switch self {
            case .http(let code): return L10n.t("updates.error.http", code)
            case .noRelease: return L10n.t("updates.error.noRelease")
            }
        }
    }

    /// Latest stable release, or the newest including pre-releases when asked.
    func latestRelease(allowPrereleases: Bool) async throws -> GitHubRelease {
        if !allowPrereleases {
            let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
            return try await fetch(GitHubRelease.self, from: url)
        }
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=30")!
        let releases = try await fetch([GitHubRelease].self, from: url)
        guard let newest = releases
            .filter({ $0.version != nil })
            .max(by: { ($0.version!) < ($1.version!) })
        else { throw ClientError.noRelease }
        return newest
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sortomat", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ClientError.http(status) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
