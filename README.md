# AppUpdateKit

Checks the App Store for a newer version of the running app and offers the
standard update prompt. Zero configuration, house policy hardcoded — and
nothing else. No forced updates, no remote config, no analytics.

## Scope

One sentence: know when a newer version is on the App Store and let the user
act on it.

Explicitly out of scope:

- Forced/blocking updates (kill switches, minimum-version gates)
- What's New content for the *current* version — that is WhatsNewKit
- Presentation arbitration — the host presents `availableUpdate` through its
  own sheet system (SheetCoordinator / SurfaceCoordinatorKit)

## Design

- **Zero configuration.** Lookup is by bundle identifier (not App Store ID),
  the current version comes from the bundle, and the storefront comes from
  the device locale with an automatic US fallback. A host constructs
  `AppUpdateKit.AppUpdateController()` and calls one method.
- **House policy inside the kit.** Recheck throttle (1 hour), "Later"
  interval (24 hours), the 7-day snooze, and "Skip This Version" semantics
  are portfolio-wide decisions made here, not per-app tweaks.
- **Every exit is recorded.** Swiping the sheet away counts as "Later", so a
  dismissal always costs the user a postponement. Without it nothing is
  persisted, the in-memory recheck clock resets on the next cold launch, and
  the prompt returns immediately — what users report as "it asks every single
  time I open the app" (MONO #804).
- **Legacy-key compatible.** Persistence uses the exact UserDefaults keys the
  pre-kit implementations shipped (`IgnoredAppVersion`,
  `NextUpdateRemindDate`), so migrating an app preserves every user's
  existing choices with zero migration code.
- **Numeric version comparison.** Every comparison goes through `AppVersion`
  (component-wise numeric), never string ordering.
- **Never blocks launch.** Network failure, missing listing, or decode errors
  are logged and reported only through the returned outcome; the whole lookup
  runs under a kit-controlled deadline (20 s total, 15 s per request), so
  `hasCompletedCheckThisLaunch` always flips within a bound the kit controls
  and startup surface chains never wait on a prompt that will not come.

## Usage

```swift
import AppUpdateKit

// Module-qualified on purpose: the portfolio CI lint (app-update-check-lint)
// uses `AppUpdateKit.AppUpdateController(...)` as its adoption evidence.
@MainActor
enum AppUpdate {
    static let controller = AppUpdateKit.AppUpdateController()
}
```

Check on launch (and optionally on foreground; repeat calls are throttled):

```swift
.task {
    await AppUpdate.controller.checkForAppUpdate()
}
```

Present the standard sheet through your app's sheet system:

```swift
if let update = AppUpdate.controller.availableUpdate {
    AppUpdateSheetView(update: update, controller: AppUpdate.controller)
}
```

`AppUpdateSheetView` is the house announcement prompt: app icon, “New
Version”, Update Now, Don't Remind Me for 7 Days, and the store release notes
with line breaks preserved. It owns its own detent and drag indicator — hosts
must not restate them.

Every exit leads somewhere different: the close control and a swipe postpone
24 hours, the bottom line postpones a week. There is no separate "Remind Me
Later" button, because closing already is one. It is localized (en source +
de, es, fr, ja, ko, pt-BR, zh-Hans, zh-Hant).

The 7-day snooze is the only longer quiet period offered, and deliberately the
only one: there is no 30-day option and no permanent opt-out, because the
prompt exists to get people onto the current build.
`ignoreThisVersion()` stays on the controller for hosts that want a skip
action; the default sheet does not show it. Hosts with a bespoke design can
render `availableUpdate` themselves and call `remindLater()` /
`snoozeForOneWeek()` / `ignoreThisVersion()` directly — and must call
`recordDismissalIfUnresolved()` when their sheet goes away, so a swipe still
records a postponement.

A settings-page "Check for Updates" action uses `force: true`, which bypasses
both the throttle and the skip/remind suppression. The returned
`AppUpdateCheckOutcome` lets you give the user honest feedback (launch-time
callers just discard it):

```swift
switch await AppUpdate.controller.checkForAppUpdate(force: true) {
case .updateAvailable: break  // availableUpdate is published; present it
case .upToDate:        showMessage("You're on the latest version.")
case .notListed, .failed, .suppressed, .throttled:
    showMessage("Couldn't check for updates. Try again later.")
}
```

Concurrent calls coalesce onto the in-flight check; a forced call that lands
while an automatic check is running waits for it and then runs its own forced
pass, so the user's explicit request is never silently dropped.

`hasCompletedCheckThisLaunch` lets a *lower-priority* candidate wait so it
cannot sneak in while an update prompt might still arrive. It is not a license
to stall every launch surface on this lookup. If What's New (or any other
local candidate) is already ready, present it now; start the check in the
background and re-arbitrate after dismiss. Awaiting the lookup to "keep update
first" loses the whole round when the user navigates during the wait, and a
process-once check cannot retry.

## Requirements

- iOS 17 / macOS 14
- Swift 6

## Installation

```swift
.package(url: "https://github.com/Jewel591/AppUpdateKit.git", from: "0.1.0")
```

## License

MIT
