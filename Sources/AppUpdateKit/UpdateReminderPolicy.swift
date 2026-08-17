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
        defaults.set(now.addingTimeInterval(remindLaterInterval), forKey: nextRemindDateKey)
    }
}
