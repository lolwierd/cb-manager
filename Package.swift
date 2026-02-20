// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cb-manager",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CBManager", targets: ["CBManager"])
    ],
    targets: [
        .executableTarget(
            name: "CBManager",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CBManagerTests",
            dependencies: ["CBManager"]
        )
    ]
)
