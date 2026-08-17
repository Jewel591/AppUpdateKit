import Foundation
import Testing

@testable import AppUpdateKit

@MainActor
struct AppUpdateControllerTests {
    private func makeController(
        client: MockLookupClient,
        currentVersion: String = "1.0.0",
        storefront: String? = "CN",
        defaults: UserDefaults = makeIsolatedDefaults(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AppUpdateController {
        AppUpdateController(
            client: client,
            bundleIdentifier: "com.example.testapp",
            currentVersion: currentVersion,
            storefront: storefront,
            defaults: defaults,
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
}
