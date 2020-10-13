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
        .package(url: "https://github.com/nachoBonafonte/opentelemetry-swift.git", .branch("develop")),
    ],
    targets: [
        .target(
            name: "DatadogSDKTesting",
            dependencies: [
                .product(name: "DatadogExporter", package: "opentelemetry-swift"),
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
