import Foundation

@testable import AppUpdateKit

/// Records lookups and replays scripted results, keyed by storefront.
final class MockLookupClient: AppStoreLookupClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requestedStorefronts: [String?] = []
    private let result: @Sendable (String?) throws -> AppStoreRelease?

    init(result: @escaping @Sendable (String?) throws -> AppStoreRelease?) {
        self.result = result
    }

    convenience init(release: AppStoreRelease?) {
        self.init { _ in release }
    }

    var requestedStorefronts: [String?] {
        lock.withLock { _requestedStorefronts }
    }

    var callCount: Int { requestedStorefronts.count }

    private func record(_ storefront: String?) {
        lock.withLock { _requestedStorefronts.append(storefront) }
    }

    func latestRelease(
        bundleIdentifier: String,
        storefront: String?
    ) async throws -> AppStoreRelease? {
        record(storefront)
        return try result(storefront)
    }
}

func makeRelease(
    version: String,
    releaseNotes: String? = "Bug fixes.",
    appName: String = "TestApp"
) -> AppStoreRelease {
    AppStoreRelease(
        appName: appName,
        version: version,
        releaseNotes: releaseNotes,
        releaseDate: nil,
        storeURL: URL(fileURLWithPath: "/apps.apple.com/app/id123456789")
    )
}

func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "AppUpdateKitTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        return .standard
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
