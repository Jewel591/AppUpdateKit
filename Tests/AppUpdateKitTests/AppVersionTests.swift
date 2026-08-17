import Foundation
import Testing

@testable import AppUpdateKit

struct AppVersionTests {
    @Test func numericComparisonBeatsLexicographicTrap() {
        #expect(AppVersion("9.0") < AppVersion("10.0"))
        #expect(AppVersion("26.9.1") < AppVersion("26.10.0"))
        #expect(!(AppVersion("10.0") < AppVersion("9.0")))
    }

    @Test func shorterVersionIsPaddedWithZeros() {
        #expect(AppVersion("1.2") == AppVersion("1.2.0"))
        #expect(AppVersion("1.2") < AppVersion("1.2.1"))
        #expect(AppVersion("2") > AppVersion("1.9.9"))
    }

    @Test func equalVersionsAreNotNewer() {
        #expect(AppVersion("3.1.4") == AppVersion("3.1.4"))
        #expect(!(AppVersion("3.1.4") > AppVersion("3.1.4")))
    }

    @Test func nonNumericComponentsCompareAsZero() {
        // A malformed remote value must never accidentally claim to be newer.
        #expect(AppVersion("1.beta") == AppVersion("1.0"))
        #expect(AppVersion("1.beta") < AppVersion("1.1"))
    }
}
