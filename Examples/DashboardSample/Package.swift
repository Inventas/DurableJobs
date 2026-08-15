// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DurableJobsDashboardSample",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "DurableJobsDashboardSample",
            targets: ["DurableJobsDashboardSample"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(
            url: "https://github.com/groue/GRDB.swift",
            from: "7.11.1"
        ),
    ],
    targets: [
        .executableTarget(
            name: "DurableJobsDashboardSample",
            dependencies: [
                .product(name: "DurableJobs", package: "DurableJobs"),
                .product(name: "DurableJobsDashboard", package: "DurableJobs"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "DurableJobsDashboardSampleTests",
            dependencies: [
                "DurableJobsDashboardSample",
                .product(name: "DurableJobs", package: "DurableJobs"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
