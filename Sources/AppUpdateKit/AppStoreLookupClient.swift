import Foundation

/// The latest release of this app on the App Store, as reported by the
/// iTunes Lookup API.
public struct AppStoreRelease: Equatable, Sendable {
    public let appName: String
    public let version: String
    public let releaseNotes: String?
    public let releaseDate: Date?
    public let storeURL: URL

    public init(
        appName: String,
        version: String,
        releaseNotes: String?,
        releaseDate: Date?,
        storeURL: URL
    ) {
        self.appName = appName
        self.version = version
        self.releaseNotes = releaseNotes
        self.releaseDate = releaseDate
        self.storeURL = storeURL
    }
}

/// Abstraction over the App Store lookup so the controller is fully testable.
public protocol AppStoreLookupClient: Sendable {
    /// Returns the latest release for `bundleIdentifier` in `storefront`
    /// (ISO country code), or nil when the storefront has no listing.
    func latestRelease(
        bundleIdentifier: String,
        storefront: String?
    ) async throws -> AppStoreRelease?
}

/// Production client backed by the official iTunes Lookup API.
///
/// Looks up by bundle identifier on purpose: the app always knows its own
/// bundle ID, so hosts need zero configuration — no per-app App Store ID.
public struct ITunesLookupClient: AppStoreLookupClient {
    public enum LookupError: Error {
        case invalidResponse
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func latestRelease(
        bundleIdentifier: String,
        storefront: String?
    ) async throws -> AppStoreRelease? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        var queryItems = [URLQueryItem(name: "bundleId", value: bundleIdentifier)]
        if let storefront, !storefront.isEmpty {
            queryItems.append(URLQueryItem(name: "country", value: storefront))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw LookupError.invalidResponse
        }

        // A per-request timeout well under the controller's total deadline;
        // the lookup is a launch-time side capability and must fail fast.
        let request = URLRequest(url: url, timeoutInterval: 15)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw LookupError.invalidResponse
        }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> AppStoreRelease? {
        let payload = try JSONDecoder().decode(LookupResponse.self, from: data)
        guard let result = payload.results.first,
              let storeURL = URL(string: result.trackViewUrl)
        else {
            return nil
        }
        return AppStoreRelease(
            appName: result.trackName,
            version: result.version,
            releaseNotes: result.releaseNotes,
            releaseDate: result.currentVersionReleaseDate.flatMap {
                ISO8601DateFormatter().date(from: $0)
            },
            storeURL: storeURL
        )
    }

    private struct LookupResponse: Decodable {
        let results: [LookupResult]
    }

    private struct LookupResult: Decodable {
        let trackName: String
        let version: String
        let releaseNotes: String?
        let currentVersionReleaseDate: String?
        let trackViewUrl: String
    }
}
