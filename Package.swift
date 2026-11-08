// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RightClick",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RightClickCore", targets: ["RightClickCore"]),
        .executable(name: "rightclick-action-runner", targets: ["RightClickActionRunnerService"]),
        .executable(name: "rightclick-app-preview", targets: ["RightClickAppPreview"])
    ],
    dependencies: [],
    targets: [
        .target(name: "RightClickCore"),
        .executableTarget(
            name: "RightClickActionRunnerService",
            dependencies: ["RightClickCore"]
        ),
        .executableTarget(
            name: "RightClickAppPreview",
            dependencies: ["RightClickCore"]
        ),
        .target(
            name: "RightClickFinderExtension",
            dependencies: ["RightClickCore"]
        ),
        .testTarget(
            name: "RightClickCoreTests",
            dependencies: ["RightClickCore"]
        ),
        .testTarget(
            name: "RightClickAppPreviewTests",
            dependencies: ["RightClickAppPreview", "RightClickCore"]
        )
    ]
)
