import Foundation
import Testing

@testable import AppUpdateKit

@MainActor
struct AppUpdateControllerTests {
    private func makeController(
        client: any AppStoreLookupClient,
        currentVersion: String = "1.0.0",
        storefront: String? = "CN",
        defaults: UserDefaults = makeIsolatedDefaults(),
        lookupDeadline: TimeInterval = 20,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AppUpdateController {
        AppUpdateController(
            client: client,
            bundleIdentifier: "com.example.testapp",
            currentVersion: currentVersion,
            storefront: storefront,
            defaults: defaults,
            lookupDeadline: lookupDeadline,
            now: now
        )
    }

    @Test func publishesUpdateWhenStoreVersionIsNewer() async {
        let client = MockLookupClient(release: makeRelease(version: "1.1.0"))
        let controller = makeController(client: client)

        await controller.checkForAppUpdate()

        #expect(controller.availableUpdate?.latestVersion == "1.1.0")
        #expect(controller.availableUpdate?.currentVersion == "1.0.0")
        #expect(controller.hasCompletedCheckThisLaunch)
    }

    @Test func staysQuietWhenStoreVersionIsNotNewer() async {
        let client = MockLookupClient(release: makeRelease(version: "1.0.0"))
        let controller = makeController(client: client)

        await controller.checkForAppUpdate()

        #expect(controller.availableUpdate == nil)
        #expect(controller.hasCompletedCheckThisLaunch)
    }

    @Test func lookupFailureCompletesQuietlyWithoutUpdate() async {
        struct Failure: Error {}
        let client = MockLookupClient { _ in throw Failure() }
        let controller = makeController(client: client)

        await controller.checkForAppUpdate()

        #expect(controller.availableUpdate == nil)
        #expect(controller.hasCompletedCheckThisLaunch)
    }

    @Test func missingListingCompletesQuietly() async {
        let client = MockLookupClient(release: nil)
        let controller = makeController(client: client)

        await controller.checkForAppUpdate()

        #expect(controller.availableUpdate == nil)
        #expect(controller.hasCompletedCheckThisLaunch)
    }

    @Test func fallsBackToUnitedStatesStorefront() async {
        let client = MockLookupClient { storefront in
            storefront == "us" ? makeRelease(version: "2.0.0") : nil
        }
        let controller = makeController(client: client, storefront: "CN")

        await controller.checkForAppUpdate()

        #expect(client.requestedStorefronts == ["cn", "us"])
        #expect(controller.availableUpdate?.latestVersion == "2.0.0")
    }

    @Test func skippedVersionIsSuppressedButForceOverrides() async {
        let defaults = makeIsolatedDefaults()
        let client = MockLookupClient(release: makeRelease(version: "1.1.0"))
        let controller = makeController(client: client, defaults: defaults)

        await controller.checkForAppUpdate()
        controller.ignoreThisVersion()
        #expect(controller.availableUpdate == nil)

        let second = makeController(client: client, defaults: defaults)
        await second.checkForAppUpdate()
        #expect(second.availableUpdate == nil)
        #expect(second.hasCompletedCheckThisLaunch)

        await second.checkForAppUpdate(force: true)
        #expect(second.availableUpdate?.latestVersion == "1.1.0")
    }

    @Test func skippingOnlySuppressesTheSkippedVersion() async {
        let defaults = makeIsolatedDefaults()
        let client = MockLookupClient(release: makeRelease(version: "1.1.0"))
        let controller = makeController(client: client, defaults: defaults)
        await controller.checkForAppUpdate()
        controller.ignoreThisVersion()

        let newerClient = MockLookupClient(release: makeRelease(version: "1.2.0"))
        let second = makeController(client: newerClient, defaults: defaults)
        await second.checkForAppUpdate()
        #expect(second.availableUpdate?.latestVersion == "1.2.0")
    }

    @Test func remindLaterSuppressesUntilIntervalElapses() async {
        let defaults = makeIsolatedDefaults()
        let start = Date()
        let client = MockLookupClient(release: makeRelease(version: "1.1.0"))

        let controller = makeController(
            client: client, defaults: defaults, now: { start })
        await controller.checkForAppUpdate()
        controller.remindLater()
        #expect(controller.availableUpdate == nil)

        let within = makeController(
            client: client, defaults: defaults,
            now: { start.addingTimeInterval(23 * 3600) })
        await within.checkForAppUpdate()
        #expect(within.availableUpdate == nil)

        let after = makeController(
            client: client, defaults: defaults,
            now: { start.addingTimeInterval(25 * 3600) })
        await after.checkForAppUpdate()
        #expect(after.availableUpdate?.latestVersion == "1.1.0")
    }

    @Test func repeatChecksAreThrottledWithinTheRecheckInterval() async {
        let start = Date()
        let client = MockLookupClient(release: makeRelease(version: "1.1.0"))
        let controller = makeController(client: client, now: { start })

        await controller.checkForAppUpdate()
        // cn miss is impossible here, so exactly one lookup per check.
        let callsAfterFirst = client.callCount
        await controller.checkForAppUpdate()
        #expect(client.callCount == callsAfterFirst)

        await controller.checkForAppUpdate(force: true)
        #expect(client.callCount > callsAfterFirst)
    }

    @Test func missingBundleFactsCompleteWithoutLookup() async {
        let client = MockLookupClient(release: makeRelease(version: "9.9.9"))
        let controller = AppUpdateController(
            client: client,
            bundleIdentifier: "",
            currentVersion: "1.0.0",
            storefront: "US",
            defaults: makeIsolatedDefaults()
        )

        await controller.checkForAppUpdate()

        #expect(client.callCount == 0)
        #expect(controller.availableUpdate == nil)
        #expect(controller.hasCompletedCheckThisLaunch)
    }

    /// The exact legacy keys are a migration contract: MONO / CodeCat / Filmo
    /// shipped these key names, and adopting the kit must preserve users'
    /// existing skip and remind-later choices.
    @Test func persistenceUsesTheLegacyKeyNames() async {
        let defaults = makeIsolatedDefaults()
        let client = MockLookupClient(release: makeRelease(version: "1.1.0"))
        let controller = makeController(client: client, defaults: defaults)

        await controller.checkForAppUpdate()
        controller.remindLater()
        #expect(defaults.object(forKey: "NextUpdateRemindDate") is Date)

        await controller.checkForAppUpdate(force: true)
        controller.ignoreThisVersion()
        #expect(defaults.string(forKey: "IgnoredAppVersion") == "1.1.0")
    }

    @Test func legacySkipChoiceFromPreKitImplementationIsHonored() async {
        let defaults = makeIsolatedDefaults()
        defaults.set("1.1.0", forKey: "IgnoredAppVersion")

        let client = MockLookupClient(release: makeRelease(version: "1.1.0"))
        let controller = makeController(client: client, defaults: defaults)
        await controller.checkForAppUpdate()

        #expect(controller.availableUpdate == nil)
    }

    // MARK: - Check outcomes

    @Test func outcomeDistinguishesUpdateUpToDateNotListedAndFailure() async {
        let newer = makeController(
            client: MockLookupClient(release: makeRelease(version: "1.1.0")))
        #expect(await newer.checkForAppUpdate() == .updateAvailable)

        let same = makeController(
            client: MockLookupClient(release: makeRelease(version: "1.0.0")))
        #expect(await same.checkForAppUpdate() == .upToDate)

        let unlisted = makeController(client: MockLookupClient(release: nil))
        #expect(await unlisted.checkForAppUpdate() == .notListed)

        struct Failure: Error {}
        let failing = makeController(
            client: MockLookupClient { _ in throw Failure() })
        #expect(await failing.checkForAppUpdate() == .failed)
    }

    @Test func outcomeReportsThrottlingAndPolicySuppression() async {
        let start = Date()
        let client = MockLookupClient(release: makeRelease(version: "1.1.0"))
        let controller = makeController(client: client, now: { start })
        await controller.checkForAppUpdate()
        #expect(await controller.checkForAppUpdate() == .throttled)

        let defaults = makeIsolatedDefaults()
        defaults.set("1.1.0", forKey: "IgnoredAppVersion")
        let suppressed = makeController(client: client, defaults: defaults)
        #expect(await suppressed.checkForAppUpdate() == .suppressed)
    }

    // MARK: - Concurrent checks

    /// Reference box so the join hook's firing is observable from the test
    /// body; everything runs on the MainActor, so plain mutation is safe.
    @MainActor
    private final class JoinProbe {
        var joinCount = 0
    }

    @Test func concurrentAutomaticChecksCoalesceOntoOneLookup() async {
        let client = GatedLookupClient(release: makeRelease(version: "1.1.0"))
        let controller = makeController(client: client, storefront: "US")
        let probe = JoinProbe()
        controller.onJoinInFlightCheckForTesting = { probe.joinCount += 1 }

        async let first = controller.checkForAppUpdate()
        while client.callCount == 0 { await Task.yield() }
        let second = Task { await controller.checkForAppUpdate() }
        // Deterministic handshake: only release the lookup once the second
        // caller has provably reached the wait-on-in-flight branch.
        while probe.joinCount == 0 { await Task.yield() }
        client.open()

        #expect(await first == .updateAvailable)
        #expect(await second.value == .updateAvailable)
        #expect(client.callCount == 1)
    }

    @Test func forcedCallDuringAutomaticCheckStillRunsAForcedPass() async {
        // The automatic check will be suppressed by a recorded skip; the
        // forced call must not inherit that outcome — it owes the user a
        // fresh pass that bypasses suppression.
        let defaults = makeIsolatedDefaults()
        defaults.set("1.1.0", forKey: "IgnoredAppVersion")
        let client = GatedLookupClient(release: makeRelease(version: "1.1.0"))
        let controller = makeController(
            client: client, storefront: "US", defaults: defaults)
        let probe = JoinProbe()
        controller.onJoinInFlightCheckForTesting = { probe.joinCount += 1 }

        async let automatic = controller.checkForAppUpdate()
        while client.callCount == 0 { await Task.yield() }
        let forced = Task { await controller.checkForAppUpdate(force: true) }
        // Deterministic handshake: the forced caller must be waiting on the
        // automatic check before the gate opens, otherwise this test could
        // pass even if an overlapping force were silently dropped.
        while probe.joinCount == 0 { await Task.yield() }
        client.open()

        #expect(await automatic == .suppressed)
        #expect(await forced.value == .updateAvailable)
        #expect(client.callCount == 2)
        #expect(controller.availableUpdate?.latestVersion == "1.1.0")
    }

    // MARK: - Skip → force → Later

    @Test func choosingLaterOnAForcedResurfaceClearsTheEarlierSkip() async {
        let defaults = makeIsolatedDefaults()
        let start = Date()
        let client = MockLookupClient(release: makeRelease(version: "1.1.0"))

        let controller = makeController(
            client: client, defaults: defaults, now: { start })
        await controller.checkForAppUpdate()
        controller.ignoreThisVersion()

        await controller.checkForAppUpdate(force: true)
        #expect(controller.availableUpdate?.latestVersion == "1.1.0")
        controller.remindLater()

        // The user's last choice was "Later": after the interval the prompt
        // must resurface — the stale skip record must not suppress it forever.
        let afterInterval = makeController(
            client: client, defaults: defaults,
            now: { start.addingTimeInterval(25 * 3600) })
        await afterInterval.checkForAppUpdate()
        #expect(afterInterval.availableUpdate?.latestVersion == "1.1.0")
    }

    // MARK: - Deadline

    @Test func hungLookupCompletesWithinTheKitDeadline() async {
        let controller = makeController(
            client: NeverReturningLookupClient(), lookupDeadline: 0.2)

        let outcome = await controller.checkForAppUpdate()

        #expect(outcome == .failed)
        #expect(controller.hasCompletedCheckThisLaunch)
        #expect(controller.availableUpdate == nil)
    }
}
