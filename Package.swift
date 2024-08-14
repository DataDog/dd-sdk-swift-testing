// swift-tools-version:5.7.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "2.5.0-alpha3"
let relaseChecksum = "60971055c7941a92f3b38769215111e1feb4da3b5a094da996e0aa262847c41b"
let url = "https://github.com/DataDog/dd-sdk-swift-testing/releases/download/\(releaseVersion)/DatadogSDKTesting.zip"

let package = Package(
    name: "dd-sdk-swift-testing",
    platforms: [.macOS(.v10_13), .iOS(.v11), .tvOS(.v11)],
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
