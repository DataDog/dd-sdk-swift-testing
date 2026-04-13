// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "2.7.1"
let relaseChecksum = "b9edb5c80a388b4988e2574b2b7c289c8e4d141951029cc73b1d974fb84af109"
let url = "https://github.com/DataDog/dd-sdk-swift-testing/releases/download/\(releaseVersion)/DatadogSDKTesting.zip"

let package = Package(
    name: "dd-sdk-swift-testing",
    platforms: [.macOS(.v11), .macCatalyst(.v13), .iOS(.v15), .tvOS(.v15)],
    products: [
        .library(name: "DatadogSDKTesting",
                 targets: ["DatadogSDKTesting"]),
    ],
    targets: [
        .binaryTarget(name: "DatadogSDKTesting",
                      url: url,
                      checksum: relaseChecksum)
    ]
)
