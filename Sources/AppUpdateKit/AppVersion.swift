import Foundation

/// A marketing version parsed into numeric components for semantic comparison.
///
/// String lexicographic comparison is the classic bug in update checks
/// ("9.0" > "10.0"); every comparison in this kit goes through this type.
/// Non-numeric components (e.g. "beta") compare as 0 so a malformed remote
/// value can never claim to be newer than a well-formed local one by accident.
public struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let components: [Int]
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
        self.components = rawValue
            .split(separator: ".")
            .map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }

    public var description: String { rawValue }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
