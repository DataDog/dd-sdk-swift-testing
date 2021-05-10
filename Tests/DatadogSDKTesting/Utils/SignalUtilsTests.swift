/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class SignalUtilsTests: XCTestCase {
    func testItReturnsProperInformationForCorrectSignal() {
        let description = SignalUtils.descriptionForSignalName(signalName: "SIGTERM")
        XCTAssertFalse(description.isEmpty)
    }

    func testItReturnsEmptyForUnknownSignals() {
        let description = SignalUtils.descriptionForSignalName(signalName: "TERM")
        XCTAssertTrue(description.isEmpty)
    }
}
