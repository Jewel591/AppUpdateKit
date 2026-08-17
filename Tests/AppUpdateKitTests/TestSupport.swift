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

/// Blocks every lookup until `open()` is called — for exercising the
/// in-flight coalescing and force-during-automatic-check paths.
final class GatedLookupClient: AppStoreLookupClient, @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var _callCount = 0
    private let release: AppStoreRelease?

    init(release: AppStoreRelease?) {
        self.release = release
    }

    var callCount: Int { lock.withLock { _callCount } }

    func open() {
        let resumable: [CheckedContinuation<Void, Never>] = lock.withLock {
            isOpen = true
            let waiting = waiters
            waiters = []
            return waiting
        }
        for continuation in resumable {
            continuation.resume()
        }
    }

    func latestRelease(
        bundleIdentifier: String,
        storefront: String?
    ) async throws -> AppStoreRelease? {
        lock.withLock { _callCount += 1 }
        await withCheckedContinuation { continuation in
            let resumeNow: Bool = lock.withLock {
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
        return release
    }
}

/// Simulates a black-holed connection: the request never completes on its
/// own, only cancellation (the kit's deadline) ends it.
struct NeverReturningLookupClient: AppStoreLookupClient {
    func latestRelease(
        bundleIdentifier: String,
        storefront: String?
    ) async throws -> AppStoreRelease? {
        try await Task.sleep(for: .seconds(3600))
        return nil
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
