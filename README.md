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
  interval (24 hours), and "Skip This Version" semantics are portfolio-wide
  decisions made here, not per-app tweaks.
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
Version”, Update Now / Remind Me Later, and the store release notes with
line breaks preserved. It is localized (en source + de, es, fr, ja, ko,
pt-BR, zh-Hans, zh-Hant). `ignoreThisVersion()` stays on the controller
for hosts that want a skip action; the default sheet does not show it.
Hosts with a bespoke design can render `availableUpdate` themselves and
call `remindLater()` / `ignoreThisVersion()` directly.

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

Startup surface chains (What's New, promotions) that must not race the update
prompt can wait on `hasCompletedCheckThisLaunch`.

## Requirements

- iOS 17 / macOS 14
- Swift 6

## Installation

```swift
.package(url: "https://github.com/Jewel591/AppUpdateKit.git", from: "0.1.0")
```

## License

MIT
