// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DurableQueuerDashboardSample",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "DurableQueuerDashboardSample",
            targets: ["DurableQueuerDashboardSample"]
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
            name: "DurableQueuerDashboardSample",
            dependencies: [
                .product(name: "DurableQueuer", package: "DurableQueuer"),
                .product(name: "DurableQueuerDashboard", package: "DurableQueuer"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "DurableQueuerDashboardSampleTests",
            dependencies: [
                "DurableQueuerDashboardSample",
                .product(name: "DurableQueuer", package: "DurableQueuer"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
