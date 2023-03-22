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
                "DatadogSDKTesting"
            ]
        )
    ],
    dependencies: [
        .package(name: "opentelemetry-swift", url: "https://github.com/open-telemetry/opentelemetry-swift", from: "1.4.1"),
        .package(name: "PLCrashReporter", url: "https://github.com/microsoft/plcrashreporter.git", from: "1.11.0"),
        .package(name: "SigmaSwiftStatistics", url: "https://github.com/evgenyneu/SigmaSwiftStatistics.git", from: "9.0.2")
    ],
    targets: [
        .target(
            name: "DatadogSDKTesting",
            dependencies: [
                .product(name: "URLSessionInstrumentation", package: "opentelemetry-swift"),
                .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
                .product(name: "CrashReporter", package: "PLCrashReporter"),
                .product(name: "SigmaSwiftStatistics", package: "SigmaSwiftStatistics"),
                .target(name: "DatadogSDKTestingObjc"),
                .target(name: "EventsExporter")
            ],
            exclude: [
                "Objc"
            ]
        ),
        .target(
            name: "DatadogSDKTestingObjc",
            path: "Sources/DatadogSDKTesting/Objc"
        ),
        .target(
            name: "EventsExporter",
            dependencies: [
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift")
            ],
            exclude: [
                "llvm-cov"
            ]
        )
    ]
)
