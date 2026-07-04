import Foundation

/// A published GitHub release plus the download asset we care about.
struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let htmlURL: URL
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case prerelease
        case assets
    }

    var version: SemanticVersion? { SemanticVersion(tagName) }

    /// Prefer a DMG, fall back to a zip.
    var preferredAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
            ?? assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }
}
