// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DurableJobs",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(name: "DurableJobs", targets: ["DurableJobs"]),
        .library(
            name: "DurableJobsBackgroundTasks",
            targets: ["DurableJobsBackgroundTasks"]
        ),
        .library(
            name: "DurableJobsDashboard",
            targets: ["DurableJobsDashboard"]
        ),
        .library(
            name: "DurableJobsTestSupport",
            targets: ["DurableJobsTestSupport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/FabrizioBrancati/Queuer", from: "4.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
    ],
    targets: [
        .target(
            name: "DurableJobs",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Queuer", package: "Queuer"),
            ]
        ),
        .target(
            name: "DurableJobsBackgroundTasks",
            dependencies: ["DurableJobs"]
        ),
        .target(
            name: "DurableJobsDashboard",
            dependencies: ["DurableJobs"]
        ),
        .target(
            name: "DurableJobsTestSupport",
            dependencies: [
                "DurableJobs",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "DurableJobsTests",
            dependencies: [
                "DurableJobs",
                "DurableJobsTestSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "DurableJobsBackgroundTasksTests",
            dependencies: [
                "DurableJobsBackgroundTasks",
                "DurableJobsTestSupport",
            ]
        ),
        .testTarget(
            name: "DurableJobsDashboardTests",
            dependencies: [
                "DurableJobsDashboard",
                "DurableJobsTestSupport",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
