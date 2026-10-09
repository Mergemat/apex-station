// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ApexStation",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure protocol and report logic. No hardware access, fully unit-tested.
        .target(name: "ApexKit"),
        // The Mac app: settings channel, live view, UI.
        .executableTarget(
            name: "ApexStation",
            dependencies: ["ApexKit"],
            linkerSettings: [
                .linkedFramework("CoreHID"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "ApexKitTests", dependencies: ["ApexKit"]),
    ]
)
