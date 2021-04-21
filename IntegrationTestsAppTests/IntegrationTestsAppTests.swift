//
//  IntegrationTestsAppTests.swift
//  IntegrationTestsAppTests
//
//  Created by Ignacio Bonafonte Arruga on 24/3/21.
//

import XCTest

class IntegrationTestsAppTests: XCTestCase {
    func testApplicationLaunches() throws {
        // UI tests must launch the application that they test. Just by running it means
        // dependencies are correctly solved.
        let app = XCUIApplication()
        app.launch()
    }
}
