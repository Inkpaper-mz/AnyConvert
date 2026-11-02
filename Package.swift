// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnyConvert",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AnyConvert", targets: ["AnyConvert"])
    ],
    targets: [
        .executableTarget(
            name: "AnyConvert",
            path: "Sources/AnyConvert",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
