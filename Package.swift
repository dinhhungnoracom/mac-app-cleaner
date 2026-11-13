// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacAppCleaner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacAppCleaner", targets: ["MacAppCleaner"])
    ],
    targets: [
        .executableTarget(
            name: "MacAppCleaner",
            path: "Sources/MacAppCleaner",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreServices")
            ]
        )
    ]
)
