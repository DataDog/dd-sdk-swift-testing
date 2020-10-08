// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "dd-sdk-swift-testing",
    platforms: [.macOS(.v10_13),
                .iOS(.v11),
                .tvOS(.v11),
                .watchOS(.v4)],
    products: [
        .library(
            name: "DatadogSDKTesting",
            type: .dynamic,
            targets: [
                "DatadogSDKTesting",
                "DatadogSDKTestingObjc",
            ]
        ),
    ],
    dependencies: [
        .package(url: "git@github.com:DataDog/dd-opentelemetry-exporter-swift.git", .branch("master")),
    ],
    targets: [
        .target(
            name: "DatadogSDKTesting",
            dependencies: [
                .product(name: "DatadogExporter", package: "dd-opentelemetry-exporter-swift"),
            ],
            exclude: [
                "objc",
            ]
        ),
        .target(
            name: "DatadogSDKTestingObjc",
            path: "Sources/DatadogSDKTesting/objc"
        ),
        .testTarget(
            name: "DatadogSDKTestingTests",
            dependencies: [
                "DatadogSDKTesting"
            ],
            path: "Tests/DatadogSDKTesting",
            exclude: [
                "objc",
            ]
        ),
    ]
)
