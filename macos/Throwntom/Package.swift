// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Throwntom",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "ThrowntomClient"),
        .target(name: "ThrowntomUI", dependencies: ["ThrowntomClient"]),
        .executableTarget(name: "Throwntom", dependencies: ["ThrowntomUI"]),
        .testTarget(name: "ThrowntomClientTests", dependencies: ["ThrowntomClient"]),
        .testTarget(name: "ThrowntomUITests", dependencies: ["ThrowntomUI", "ThrowntomClient"]),
    ]
)
