// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dpk-starter",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/Therealdk8890/DProvenanceKit", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "StarterDemo",
            dependencies: [
                .product(name: "DProvenanceKit", package: "DProvenanceKit"),
                .product(name: "DProvenanceFoundationModels", package: "DProvenanceKit"),
            ]
        )
    ]
)
