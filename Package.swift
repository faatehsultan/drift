// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Drift",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "Drift",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Drift",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
