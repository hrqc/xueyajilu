// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BPHealth",
    platforms: [.iOS(.v17)],
    products: [.library(name: "BPHealthCore", targets: ["BPHealthCore"])],
    targets: [
        .target(name: "BPHealthCore", path: "BPHealth", exclude: ["BPHealthApp.swift", "BPHealth.entitlements", "PrivacyInfo.xcprivacy", "Views"], resources: [.process("Resources")], linkerSettings: [.linkedFramework("HealthKit", .when(platforms: [.iOS]))]),
        .testTarget(name: "BPHealthTests", dependencies: ["BPHealthCore"], path: "BPHealthTests", exclude: ["BPHealthUITests.swift"])
    ]
)
