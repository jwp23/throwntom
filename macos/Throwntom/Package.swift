// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Throwntom",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ThrowntomClient"),
        .executableTarget(name: "Throwntom", dependencies: ["ThrowntomClient"]),
        .testTarget(name: "ThrowntomClientTests", dependencies: ["ThrowntomClient"]),
    ]
)
