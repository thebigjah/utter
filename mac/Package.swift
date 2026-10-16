// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Utter",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "UtterCore"),
        .executableTarget(
            name: "Utter",
            dependencies: ["UtterCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "UtterCoreTests", dependencies: ["UtterCore"]),
    ],
    swiftLanguageModes: [.v5]
)
