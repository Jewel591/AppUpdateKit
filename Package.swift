// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppUpdateKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AppUpdateKit", targets: ["AppUpdateKit"]),
    ],
    targets: [
        .target(
            name: "AppUpdateKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AppUpdateKitTests",
            dependencies: ["AppUpdateKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
