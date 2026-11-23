// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sleepless",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Sleepless", targets: ["Sleepless"])],
    targets: [
        .target(name: "SleeplessCore"),
        .executableTarget(name: "Sleepless", dependencies: ["SleeplessCore"]),
        .testTarget(name: "SleeplessCoreTests", dependencies: ["SleeplessCore"]),
        .testTarget(name: "SleeplessIconTests", dependencies: ["Sleepless", "SleeplessCore"])
    ]
)