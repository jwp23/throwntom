// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Throwntom",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ThrowntomClient"),
        .target(name: "ThrowntomUI", dependencies: ["ThrowntomClient"]),
        .executableTarget(name: "Throwntom", dependencies: ["ThrowntomUI"]),
        .executableTarget(name: "ThrowntomAlert", dependencies: ["ThrowntomClient"]),
        .testTarget(name: "ThrowntomClientTests", dependencies: ["ThrowntomClient"]),
        .testTarget(name: "ThrowntomUITests", dependencies: ["ThrowntomUI", "ThrowntomClient"]),
    ]
)
