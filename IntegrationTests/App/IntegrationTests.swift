/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

internal import OpenTelemetryApi
import DatadogSDKTesting
import XCTest

let tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: "Custom Tracer", instrumentationVersion: nil)

public class UnskippableTestCase: XCTestCase, ExtendableTaggedType {
    public static func extendableTypeTags() -> ExtendableTypeTags {
        withTagger { tagger in
            tagger.set(type: .tiaSkippable, to: false)
        }
    }
}

public class BasicPass: UnskippableTestCase {
    func testBasicPass() throws {
        print("BasicPass")
        XCTAssert(true)
    }
}

public class BasicSkip: UnskippableTestCase {
    func testBasicSkip() throws {
        print("BasicSkip")
        try XCTSkipIf(true)
    }
}

public class BasicError: UnskippableTestCase {
    func testBasicError() throws {
        print("BasicError")
        XCTAssert(false)
    }
}

public class AsynchronousPass: UnskippableTestCase {
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

public class AsynchronousSkip: UnskippableTestCase {
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

public class AsynchronousError: UnskippableTestCase {
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

public class Benchmark: UnskippableTestCase {
    func testBenchmark() throws {
        measure {
            print("Benchmark")
        }
    }
}

public class Flaky: UnskippableTestCase {
    func testFlaky() {
        print("Flaky")
        XCTAssertEqual((0...2).randomElement(), 0)
    }
}

public class NetworkIntegration: UnskippableTestCase {
    func testNetworkIntegration() throws {
        print("NetworkIntegration")

        let url = URL(string: "https://github.com/DataDog/dd-sdk-swift-testing")!
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
