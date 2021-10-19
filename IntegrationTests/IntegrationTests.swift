/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@_implementationOnly import OpenTelemetrySdk
import XCTest

let tracer = OpenTelemetrySDK.instance.tracerProvider.get(instrumentationName: "Custom Tracer")

class BasicPass: XCTestCase {
    func testBasicPass() throws {
        print("BasicPass")
        XCTAssert(true)
    }
}

class BasicSkip: XCTestCase {
    func testBasicSkip() throws {
        print("BasicSkip")
        try XCTSkipIf(true)
    }
}

class BasicError: XCTestCase {
    func testBasicError() throws {
        print("BasicError")
        XCTAssert(false)
    }
}

class AsynchronousPass: XCTestCase {
    func testAsynchronousPass() throws {
        print("AsynchronousPass")
        let expec = expectation(description: "AsynchronousPass")

        DispatchQueue.global().async {
            let span = tracer.spanBuilder(spanName: "AsyncWork").startSpan()
            sleep(1)
            span.end()
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
    func testAsynchronousSkip() throws {
        print("AsynchronousSkip")
        let expec = expectation(description: "AsynchronousPass")

        DispatchQueue.global().async {
            let span = tracer.spanBuilder(spanName: "AsyncWork").startSpan()
            sleep(1)
            span.end()
            expec.fulfill()
        }

        waitForExpectations(timeout: 30) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
        try XCTSkipIf(true)
    }
}

class AsynchronousError: XCTestCase {
    func testAsynchronousError() throws {
        print("AsynchronousError")
        let expec = expectation(description: "AsynchronousPass")

        DispatchQueue.global().async {
            let span = tracer.spanBuilder(spanName: "AsyncWork").startSpan()
            sleep(1)
            XCTAssert(false)
            span.end()
            expec.fulfill()
        }

        waitForExpectations(timeout: 30) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }
}

class Benchmark: XCTestCase {
    func testBenchmark() throws {
        measure {
            print("Benchmark")
        }
    }
}

class NetworkIntegration: XCTestCase {
    func testNetworkIntegration() throws {
        print("NetworkIntegration")

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
