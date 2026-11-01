// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HaushaltsbuchKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "HaushaltsbuchAPI", targets: ["HaushaltsbuchAPI"]),
        .library(name: "HaushaltsbuchCore", targets: ["HaushaltsbuchCore"]),
        .library(name: "HaushaltsbuchData", targets: ["HaushaltsbuchData"]),
        .library(name: "HaushaltsbuchUI", targets: ["HaushaltsbuchUI"]),
    ],
    targets: [
        .target(name: "HaushaltsbuchAPI"),
        .target(name: "HaushaltsbuchCore"),
        .target(name: "HaushaltsbuchData", dependencies: ["HaushaltsbuchCore", "HaushaltsbuchAPI"]),
        .target(name: "HaushaltsbuchUI", dependencies: ["HaushaltsbuchData", "HaushaltsbuchCore"]),
        .testTarget(name: "HaushaltsbuchAPITests", dependencies: ["HaushaltsbuchAPI"]),
        .testTarget(name: "HaushaltsbuchCoreTests", dependencies: ["HaushaltsbuchCore"]),
        .testTarget(name: "HaushaltsbuchDataTests", dependencies: ["HaushaltsbuchData"]),
        .testTarget(name: "HaushaltsbuchUITests", dependencies: ["HaushaltsbuchUI"]),
    ],
    swiftLanguageModes: [.v6]
)
