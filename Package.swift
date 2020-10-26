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
        .package(url: "https://github.com/nachoBonafonte/opentelemetry-swift.git", .revision("2f7954d489617df596ffc6e686b16d4298d14963")),
        .package(url: "https://github.com/microsoft/plcrashreporter.git", .revision("af3a0a1248adc690354de07e5e36e8bcc7314e72")),
        .package(url: "https://github.com/evgenyneu/SigmaSwiftStatistics.git", from: "9.0.2"),
    ],
    targets: [
        .target(
            name: "DatadogSDKTesting",
            dependencies: [
                .product(name: "DatadogExporter", package: "opentelemetry-swift"),
                .product(name: "CrashReporter", package: "PLCrashReporter"),
                .product(name: "SigmaSwiftStatistics", package: "SigmaSwiftStatistics"),
            ],
            exclude: [
                "Objc",
            ]
        ),
        .target(
            name: "DatadogSDKTestingObjc",
            path: "Sources/DatadogSDKTesting/Objc"
        ),
        .testTarget(
            name: "DatadogSDKTestingTests",
            dependencies: [
                "DatadogSDKTesting"
            ],
            path: "Tests/DatadogSDKTesting",
            exclude: [
                "Objc",
            ]
        ),
    ]
)
