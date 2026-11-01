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
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.14.3"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.3"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "HaushaltsbuchAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
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
