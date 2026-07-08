// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NativeStackKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NativeStackCore", targets: ["NativeStackCore"]),
        .library(name: "NativeStackClient", targets: ["NativeStackClient"]),
        .executable(name: "nativestack", targets: ["NativeStackCLI"]),
        .executable(name: "NativeStackApp", targets: ["NativeStackApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "NativeStackCore"),
        .target(
            name: "NativeStackClient",
            dependencies: ["NativeStackCore"]
        ),
        .target(
            name: "NativeStackAPIServer",
            dependencies: ["NativeStackClient", "NativeStackCore"]
        ),
        .executableTarget(
            name: "NativeStackCLI",
            dependencies: [
                "NativeStackClient",
                "NativeStackCore",
                "NativeStackAPIServer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "NativeStackApp",
            dependencies: ["NativeStackClient", "NativeStackCore"]
        ),
    ]
)
