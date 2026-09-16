// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Elbowroom",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ElbowroomKit", targets: ["ElbowroomKit"]),
        .executable(name: "Elbowroom", targets: ["Elbowroom"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
    ],
    targets: [
        .target(name: "AuthorizedAppMoveCore"),
        .executableTarget(name: "ElbowroomAppMover", dependencies: ["AuthorizedAppMoveCore"]),
        .target(
            name: "ElbowroomKit",
            path: "Sources/ElbowroomKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Elbowroom",
            dependencies: ["ElbowroomKit", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Elbowroom"
        ),
        .executableTarget(
            name: "ElbowroomSnapshots",
            dependencies: ["ElbowroomKit"],
            path: "Sources/ElbowroomSnapshots"
        ),
        .executableTarget(
            name: "ElbowroomBench",
            dependencies: ["ElbowroomKit"],
            path: "Sources/ElbowroomBench"
        ),
        .testTarget(
            name: "ElbowroomTests",
            dependencies: ["ElbowroomKit", "AuthorizedAppMoveCore"],
            path: "Tests/ElbowroomTests"
        ),
    ]
)
