// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pik",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pik", targets: ["Pik"]),
    ],
    targets: [
        .target(
            name: "PikKit",
            path: "Sources/PikKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Pik",
            dependencies: ["PikKit"],
            path: "Sources/Pik",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PikIconGen",
            dependencies: ["PikKit"],
            path: "Sources/PikIconGen",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PikKitTests",
            dependencies: ["PikKit"],
            path: "Tests/PikKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
