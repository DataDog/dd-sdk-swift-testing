// swift-tools-version:5.3
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
        ),
    ],
    dependencies: [
        .package(name: "opentelemetry-swift", url: "https://github.com/open-telemetry/opentelemetry-swift.git", .revision("044f0fd58e8c4fb1eef42045945cc240e820d94c")),
        .package(name: "PLCrashReporter", url: "https://github.com/microsoft/plcrashreporter.git", from: "1.8.1"),
        .package(name: "SigmaSwiftStatistics",url: "https://github.com/evgenyneu/SigmaSwiftStatistics.git", from: "9.0.2"),
    ],
    targets: [
        .target(
            name: "DatadogSDKTesting",
            dependencies: [
                .product(name: "DatadogExporter", package: "opentelemetry-swift"),
                .product(name: "CrashReporter", package: "PLCrashReporter", condition: .when(platforms: [.iOS, .macOS, .tvOS])),
                .product(name: "SigmaSwiftStatistics", package: "SigmaSwiftStatistics"),
                .target( name: "DatadogSDKTestingObjc"),
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
