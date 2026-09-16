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
    targets: [
        .target(
            name: "ElbowroomKit",
            path: "Sources/ElbowroomKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Elbowroom",
            dependencies: ["ElbowroomKit"],
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
            dependencies: ["ElbowroomKit"],
            path: "Tests/ElbowroomTests"
        ),
    ]
)
