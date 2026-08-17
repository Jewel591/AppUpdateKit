import Foundation
import Observation
import OSLog

/// Everything the standard update prompt needs to render.
public struct AppUpdatePresentation: Equatable, Identifiable, Sendable {
    public let appName: String
    public let currentVersion: String
    public let latestVersion: String
    public let releaseNotes: String?
    public let releaseDate: Date?
    public let storeURL: URL

    public var id: String { "\(latestVersion)|\(storeURL.absoluteString)" }
}

/// Checks the App Store for a newer version of the running app and exposes
/// the result as observable state. The host presents `availableUpdate`
/// through its own sheet system (SheetCoordinator / SurfaceCoordinatorKit
/// arbitration); this kit never presents anything by itself.
///
/// Zero configuration by design: bundle identifier, current version, and
/// storefront are all derived from the running process. Construct it
/// module-qualified — `AppUpdateKit.AppUpdateController()` — which is the
/// adoption evidence the portfolio CI lint (app-update-check-lint) anchors on.
@MainActor
@Observable
public final class AppUpdateController {
    /// Non-nil exactly when a newer version exists and the house reminder
    /// policy allows prompting. The host presents this and calls one of
    /// `remindLater()` / `ignoreThisVersion()` / `openAppStore()`.
    public private(set) var availableUpdate: AppUpdatePresentation?

    /// True once this launch's check has reached a conclusion (found an
    /// update, found none, failed, or was throttled). Startup surface chains
    /// can wait on this to know the update prompt will not arrive late.
    public private(set) var hasCompletedCheckThisLaunch = false

    public private(set) var isChecking = false

    private let client: any AppStoreLookupClient
    private let bundleIdentifier: String
    private let currentVersion: String
    private let storefront: String?
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private var lastCheckDate: Date?

    private let logger = Logger(subsystem: "AppUpdateKit", category: "AppUpdateController")

    /// Production initializer — no parameters on purpose.
    public convenience init() {
        self.init(
            client: ITunesLookupClient(),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            currentVersion: Bundle.main
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            storefront: Locale.current.region?.identifier,
            defaults: .standard,
            now: { Date() }
        )
    }

    /// Designated initializer, exposed for tests and previews.
    public init(
        client: any AppStoreLookupClient,
        bundleIdentifier: String,
        currentVersion: String,
        storefront: String?,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.bundleIdentifier = bundleIdentifier
        self.currentVersion = currentVersion
        self.storefront = storefront
        self.defaults = defaults
        self.now = now
    }

    /// Checks the App Store and, when a newer version exists and the reminder
    /// policy allows it, publishes `availableUpdate`.
    ///
    /// Never throws and never blocks the caller beyond the network call:
    /// update checking is a launch-time side capability, so failures are
    /// logged and swallowed. `force` (user tapped "Check for Updates")
    /// bypasses both the recheck throttle and the skip/remind suppression.
    public func checkForAppUpdate(force: Bool = false) async {
        guard !isChecking else { return }
        defer { hasCompletedCheckThisLaunch = true }

        guard !bundleIdentifier.isEmpty, !currentVersion.isEmpty else {
            logger.error("Missing bundle identifier or marketing version; skipping update check")
            return
        }
        if !force, let lastCheckDate,
           now().timeIntervalSince(lastCheckDate) < UpdateReminderPolicy.recheckInterval {
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            guard let release = try await lookupWithStorefrontFallback() else {
                logger.info("App Store lookup returned no listing")
                return
            }
            lastCheckDate = now()

            guard AppVersion(release.version) > AppVersion(currentVersion) else {
                if force { availableUpdate = nil }
                return
            }
            guard force || UpdateReminderPolicy.allowsPrompt(
                latestVersion: release.version, defaults: defaults, now: now()
            ) else {
                logger.info("Newer version available but suppressed by reminder policy")
                return
            }
            availableUpdate = AppUpdatePresentation(
                appName: release.appName,
                currentVersion: currentVersion,
                latestVersion: release.version,
                releaseNotes: release.releaseNotes,
                releaseDate: release.releaseDate,
                storeURL: release.storeURL
            )
        } catch {
            logger.error("App Store update check failed: \(error.localizedDescription)")
        }
    }

    /// Dismisses the prompt and resurfaces it after the house interval.
    public func remindLater() {
        UpdateReminderPolicy.recordRemindLater(defaults: defaults, now: now())
        availableUpdate = nil
    }

    /// Dismisses the prompt permanently for the offered version.
    public func ignoreThisVersion() {
        guard let availableUpdate else { return }
        UpdateReminderPolicy.recordSkippedVersion(
            availableUpdate.latestVersion, defaults: defaults)
        self.availableUpdate = nil
    }

    private func lookupWithStorefrontFallback() async throws -> AppStoreRelease? {
        // The user's storefront first; a US fallback covers apps not listed
        // in a region the device happens to be set to.
        var storefronts: [String?] = [storefront?.lowercased()]
        if storefront?.lowercased() != "us" {
            storefronts.append("us")
        }
        for candidate in storefronts {
            if let release = try await client.latestRelease(
                bundleIdentifier: bundleIdentifier, storefront: candidate
            ) {
                return release
            }
        }
        return nil
    }
}
