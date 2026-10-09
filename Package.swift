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
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // Holds the virtual Xbox controller games see. Separate because it needs an entitlement
        // macOS only honours for signed apps (or with AMFI relaxed), and Apex Station must open
        // everywhere.
        .executableTarget(
            name: "ApexPad",
            dependencies: ["ApexKit"],
            linkerSettings: [.linkedFramework("CoreHID")]
        ),
        .testTarget(name: "ApexKitTests", dependencies: ["ApexKit"], resources: [.copy("Fixtures")]),
    ]
)
