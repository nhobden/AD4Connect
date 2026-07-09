// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AD4Connect",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Protocol + config library. No UI, fully unit-testable.
        .target(
            name: "AD4ConnectKit"
        ),
        // SwiftUI application.
        .executableTarget(
            name: "AD4Connect",
            dependencies: ["AD4ConnectKit"]
        ),
        .testTarget(
            name: "AD4ConnectKitTests",
            dependencies: ["AD4ConnectKit"]
        ),
    ]
)
