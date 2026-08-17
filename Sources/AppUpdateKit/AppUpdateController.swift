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

/// What a single `checkForAppUpdate` call concluded. Launch-time callers can
/// discard it; a settings-page "Check for Updates" button uses it to give the
/// user honest feedback instead of silently doing nothing.
public enum AppUpdateCheckOutcome: Equatable, Sendable {
    /// A newer version exists; `availableUpdate` is published.
    case updateAvailable
    /// The store version is not newer than the running version.
    case upToDate
    /// The lookup succeeded but no storefront carries this bundle ID
    /// (TestFlight builds, unreleased apps).
    case notListed
    /// A newer version exists but the reminder policy (skip / remind later)
    /// suppressed the prompt. Only reachable on non-forced checks.
    case suppressed
    /// Skipped: a recent check already ran within the recheck interval.
    case throttled
    /// The lookup failed (network, HTTP, decoding, deadline, or missing
    /// bundle facts). Never blocks the caller; details are in the log.
    case failed
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
    /// Hard ceiling on one check's total network time. The completion signal
    /// (`hasCompletedCheckThisLaunch`) must arrive within a bound the kit
    /// controls — a captive portal or black-holed connection must not leave a
    /// startup surface chain waiting on the system's much longer timeouts.
    private let lookupDeadline: TimeInterval
    private var lastCheckDate: Date?
    private var inFlightCheck: Task<AppUpdateCheckOutcome, Never>?

    private let logger = Logger(subsystem: "AppUpdateKit", category: "AppUpdateController")

    /// Test-only hook, fired when a call observes an in-flight check and is
    /// about to await it. Lets concurrency tests deterministically confirm
    /// "the second caller reached the wait branch" before releasing a gated
    /// lookup — a bare `Task.yield()` cannot guarantee that ordering.
    var onJoinInFlightCheckForTesting: (@MainActor () -> Void)?

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

    /// Designated initializer for tests and previews. Deliberately internal:
    /// the zero-config contract means production code has nothing to inject,
    /// and exposing these knobs invites checking the wrong app or version.
    init(
        client: any AppStoreLookupClient,
        bundleIdentifier: String,
        currentVersion: String,
        storefront: String?,
        defaults: UserDefaults = .standard,
        lookupDeadline: TimeInterval = 20,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.bundleIdentifier = bundleIdentifier
        self.currentVersion = currentVersion
        self.storefront = storefront
        self.defaults = defaults
        self.lookupDeadline = lookupDeadline
        self.now = now
    }

    /// Checks the App Store and, when a newer version exists and the reminder
    /// policy allows it, publishes `availableUpdate`.
    ///
    /// Never throws and never blocks the caller beyond a bounded network
    /// call: update checking is a launch-time side capability, so failures
    /// are logged and reported only through the returned outcome. `force`
    /// (user tapped "Check for Updates") bypasses both the recheck throttle
    /// and the skip/remind suppression.
    ///
    /// Concurrent calls coalesce onto the in-flight check. A forced call that
    /// arrives while an automatic check is running waits for it, then runs
    /// its own forced pass — the user's explicit request is never downgraded
    /// to the automatic check's throttled/suppressed semantics.
    @discardableResult
    public func checkForAppUpdate(force: Bool = false) async -> AppUpdateCheckOutcome {
        while let inFlight = inFlightCheck {
            onJoinInFlightCheckForTesting?()
            let outcome = await inFlight.value
            if inFlightCheck == inFlight { inFlightCheck = nil }
            if !force { return outcome }
        }

        let check = Task { await self.performCheck(force: force) }
        inFlightCheck = check
        let outcome = await check.value
        if inFlightCheck == check { inFlightCheck = nil }
        return outcome
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

    private func performCheck(force: Bool) async -> AppUpdateCheckOutcome {
        defer { hasCompletedCheckThisLaunch = true }

        guard !bundleIdentifier.isEmpty, !currentVersion.isEmpty else {
            logger.error("Missing bundle identifier or marketing version; skipping update check")
            return .failed
        }
        if !force, let lastCheckDate,
           now().timeIntervalSince(lastCheckDate) < UpdateReminderPolicy.recheckInterval {
            return .throttled
        }

        isChecking = true
        defer { isChecking = false }

        do {
            guard let release = try await lookupWithinDeadline() else {
                logger.info("App Store lookup returned no listing")
                return .notListed
            }
            lastCheckDate = now()

            guard AppVersion(release.version) > AppVersion(currentVersion) else {
                if force { availableUpdate = nil }
                return .upToDate
            }
            guard force || UpdateReminderPolicy.allowsPrompt(
                latestVersion: release.version, defaults: defaults, now: now()
            ) else {
                logger.info("Newer version available but suppressed by reminder policy")
                return .suppressed
            }
            availableUpdate = AppUpdatePresentation(
                appName: release.appName,
                currentVersion: currentVersion,
                latestVersion: release.version,
                releaseNotes: release.releaseNotes,
                releaseDate: release.releaseDate,
                storeURL: release.storeURL
            )
            return .updateAvailable
        } catch {
            logger.error("App Store update check failed: \(error.localizedDescription)")
            return .failed
        }
    }

    private struct LookupDeadlineExceeded: Error {}

    /// Races the storefront-fallback lookup against the kit's deadline so a
    /// hung connection cannot stall the check indefinitely.
    private func lookupWithinDeadline() async throws -> AppStoreRelease? {
        let client = self.client
        let bundleIdentifier = self.bundleIdentifier
        let storefronts = storefrontCandidates()
        let deadline = lookupDeadline

        return try await withThrowingTaskGroup(of: AppStoreRelease?.self) { group in
            group.addTask {
                // The user's storefront first; a US fallback covers apps not
                // listed in a region the device happens to be set to.
                for candidate in storefronts {
                    if let release = try await client.latestRelease(
                        bundleIdentifier: bundleIdentifier, storefront: candidate
                    ) {
                        return release
                    }
                }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: .seconds(deadline))
                throw LookupDeadlineExceeded()
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    private func storefrontCandidates() -> [String?] {
        var storefronts: [String?] = [storefront?.lowercased()]
        if storefront?.lowercased() != "us" {
            storefronts.append("us")
        }
        return storefronts
    }
}
