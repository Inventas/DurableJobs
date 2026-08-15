// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DurableQueuer",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(name: "DurableQueuer", targets: ["DurableQueuer"]),
        .library(
            name: "DurableQueuerBackgroundTasks",
            targets: ["DurableQueuerBackgroundTasks"]
        ),
        .library(
            name: "DurableQueuerDashboard",
            targets: ["DurableQueuerDashboard"]
        ),
        .library(
            name: "DurableQueuerTestSupport",
            targets: ["DurableQueuerTestSupport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/FabrizioBrancati/Queuer", from: "4.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
    ],
    targets: [
        .target(
            name: "DurableQueuer",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Queuer", package: "Queuer"),
            ]
        ),
        .target(
            name: "DurableQueuerBackgroundTasks",
            dependencies: ["DurableQueuer"]
        ),
        .target(
            name: "DurableQueuerDashboard",
            dependencies: ["DurableQueuer"]
        ),
        .target(
            name: "DurableQueuerTestSupport",
            dependencies: [
                "DurableQueuer",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "DurableQueuerTests",
            dependencies: [
                "DurableQueuer",
                "DurableQueuerTestSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "DurableQueuerBackgroundTasksTests",
            dependencies: [
                "DurableQueuerBackgroundTasks",
                "DurableQueuerTestSupport",
            ]
        ),
        .testTarget(
            name: "DurableQueuerDashboardTests",
            dependencies: [
                "DurableQueuerDashboard",
                "DurableQueuerTestSupport",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
