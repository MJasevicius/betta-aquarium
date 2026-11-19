// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BettaAquarium",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BettaAquarium",
            path: "Sources/BettaAquarium",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        )
    ]
)
