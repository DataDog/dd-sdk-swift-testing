// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "dd-sdk-swift-testing",
    platforms: [.macOS(.v10_13),
                .iOS(.v11),
                .tvOS(.v11)],
    products: [
        .library(
            name: "DatadogSDKTesting",
            type: .dynamic,
            targets: [
                "DatadogSDKTesting",
            ]
        ),
    ],
    dependencies: [
        .package(name: "opentelemetry-swift", url: "https://github.com/open-telemetry/opentelemetry-swift", from: "1.0.5"),
        .package(name: "PLCrashReporter", url: "https://github.com/microsoft/plcrashreporter.git", from: "1.9.0"),
        .package(name: "SigmaSwiftStatistics", url: "https://github.com/evgenyneu/SigmaSwiftStatistics.git", from: "9.0.2"),
        .package(name: "Kronos", url: "https://github.com/MobileNativeFoundation/Kronos", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "DatadogSDKTesting",
            dependencies: [
                .product(name: "libDatadogExporter", package: "opentelemetry-swift"),
                .product(name: "libURLSessionInstrumentation", package: "opentelemetry-swift"),
                .product(name: "libInMemoryExporter", package: "opentelemetry-swift"),
                .product(name: "CrashReporter", package: "PLCrashReporter"),
                .product(name: "SigmaSwiftStatistics", package: "SigmaSwiftStatistics"),
                .target(name: "DatadogSDKTestingObjc"),
            ],
            exclude: [
                "Objc",
            ]
        ),
        .target(
            name: "DatadogSDKTestingObjc",
            path: "Sources/DatadogSDKTesting/Objc"
        ),
    ]
)
