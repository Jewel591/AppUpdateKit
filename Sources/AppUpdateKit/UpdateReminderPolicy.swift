import Foundation

/// House-standard reminder policy. Values are portfolio-wide decisions made
/// inside the kit — hosts do not tune them per app.
///
/// The UserDefaults keys are intentionally the exact keys the pre-kit
/// implementations shipped (MONO / CodeCat / Filmo), so migrating an app to
/// the kit preserves every user's "skip this version" and "remind me later"
/// choices with zero migration code.
enum UpdateReminderPolicy {
    /// Repeat foreground checks are skipped inside this window; a cold launch
    /// always starts with a fresh in-memory clock and therefore checks once.
    static let recheckInterval: TimeInterval = 3600
    /// "Later" resurfaces the prompt on the first check after this interval.
    static let remindLaterInterval: TimeInterval = 24 * 3600
    /// The one longer quiet period offered, and deliberately the only one.
    /// A user who has seen the prompt and wants it gone needs an exit that
    /// costs one tap; without it they dismiss by swiping, which records
    /// nothing and brings the prompt back on the very next cold launch.
    /// Nothing longer is offered and there is no permanent "skip this
    /// version" button: the point of the prompt is to get people onto the
    /// current build.
    static let snoozeInterval: TimeInterval = 7 * 24 * 3600

    static let ignoredVersionKey = "IgnoredAppVersion"
    static let nextRemindDateKey = "NextUpdateRemindDate"

    /// Whether the prompt for `latestVersion` may surface right now.
    static func allowsPrompt(
        latestVersion: String,
        defaults: UserDefaults,
        now: Date
    ) -> Bool {
        if defaults.string(forKey: ignoredVersionKey) == latestVersion {
            return false
        }
        if let nextRemindDate = defaults.object(forKey: nextRemindDateKey) as? Date,
           now < nextRemindDate {
            return false
        }
        return true
    }

    static func recordSkippedVersion(_ version: String, defaults: UserDefaults) {
        defaults.set(version, forKey: ignoredVersionKey)
    }

    static func recordRemindLater(defaults: UserDefaults, now: Date) {
        postpone(by: remindLaterInterval, defaults: defaults, now: now)
    }

    static func recordSnooze(defaults: UserDefaults, now: Date) {
        postpone(by: snoozeInterval, defaults: defaults, now: now)
    }

    /// Both postponements write the same key, so the most recent choice always
    /// wins outright — a user who snoozed a week and later taps "Later" on a
    /// newer version gets 24h, not the leftover week.
    private static func postpone(by interval: TimeInterval, defaults: UserDefaults, now: Date) {
        defaults.set(now.addingTimeInterval(interval), forKey: nextRemindDateKey)
        // The user's latest choice wins: choosing "Later" on a version they
        // previously skipped (reachable via a forced check) means they want
        // to be reminded again — a lingering skip record would suppress that
        // version forever.
        defaults.removeObject(forKey: ignoredVersionKey)
    }
}
