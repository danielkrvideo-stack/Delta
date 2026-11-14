// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Delta",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Delta", targets: ["Delta"]),
        .executable(name: "DeltaUpdateInstaller", targets: ["DeltaUpdateInstaller"])
    ],
    targets: [
        .executableTarget(
            name: "Delta",
            path: "Sources/Delta"
        ),
        .executableTarget(
            name: "DeltaUpdateInstaller",
            path: "Sources/DeltaUpdateInstaller"
        )
    ]
)
