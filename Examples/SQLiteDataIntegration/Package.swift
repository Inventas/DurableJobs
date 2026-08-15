// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SQLiteDataIntegrationFixture",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "SQLiteDataIntegrationFixture",
            targets: ["SQLiteDataIntegrationFixture"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(
            url: "https://github.com/pointfreeco/sqlite-data",
            exact: "1.8.2"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift",
            from: "7.11.1"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-structured-queries",
            "0.34.0" ..< "0.35.0"
        ),
    ],
    targets: [
        .target(
            name: "SQLiteDataIntegrationFixture",
            dependencies: [
                .product(name: "DurableJobs", package: "DurableJobs"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
