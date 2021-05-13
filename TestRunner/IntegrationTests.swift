/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import XCTest

class BasicPass: XCTestCase {
    func test() throws {
        print("BasicPass")
        XCTAssert(true)
    }
}

class BasicSkip: XCTestCase {
    func test() throws {
        print("BasicSkip")
        try XCTSkipIf(true)
    }
}

class BasicError: XCTestCase {
    func test() throws {
        print("BasicError")
        XCTAssert(false)
    }
}

class AsynchronousPass: XCTestCase {
    func test() throws {
        print("AsynchronousPass")
        let expec = expectation(description: "AsynchronousPass")

        DispatchQueue.global().async {
            sleep(2)
            expec.fulfill()
        }

        waitForExpectations(timeout: 30) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }
}

class AsynchronousSkip: XCTestCase {
    func test() throws {
        print("AsynchronousSkip")
        let expec = expectation(description: "AsynchronousPass")

        DispatchQueue.global().async {
            sleep(2)
            try? XCTSkipIf(true)
            expec.fulfill()
        }

        waitForExpectations(timeout: 30) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }
}

class AsynchronousError: XCTestCase {
    func test() throws {
        print("AsynchronousError")
        let expec = expectation(description: "AsynchronousPass")

        DispatchQueue.global().async {
            sleep(2)
            XCTAssert(false)
            expec.fulfill()
        }

        waitForExpectations(timeout: 30) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }
}

class BasicNetwork: XCTestCase {
    func test() throws {
        print("BasicNetwork")

        let url = URL(string: "http://httpbin.org/get")!
        let expec = expectation(description: "GET \(url)")

        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data {
                let string = String(data: data, encoding: .utf8)
                print(string ?? "")
            }
            expec.fulfill()
        }
        task.resume()

        waitForExpectations(timeout: 30) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
            task.cancel()
        }
    }
}
