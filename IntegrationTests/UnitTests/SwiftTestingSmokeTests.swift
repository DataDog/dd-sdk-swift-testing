/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Testing
import Foundation
import DatadogSDKTesting

@Suite(.datadogTesting) struct STBasicPass {
    @Test func basicPass() {
        #expect(Bool(true))
    }
}

@Suite(.datadogTesting) struct STBasicSkip {
    @Test func basicSkip() throws {
#if compiler(>=6.3)
        try Testing.Test.cancel("skip")
#endif
    }
}

@Suite(.datadogTesting) struct STBasicError {
    @Test func basicError() {
        #expect(Bool(false))
    }
}

@Suite(.datadogTesting) struct STAsynchronousPass {
    @Test func asynchronousPass() async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }
}

@Suite(.datadogTesting) struct STAsynchronousSkip {
    @Test func asynchronousSkip() async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)
#if compiler(>=6.3)
        try Testing.Test.cancel("skip")
#endif
    }
}

@Suite(.datadogTesting) struct STAsynchronousError {
    @Test func asynchronousError() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(Bool(false))
    }
}

//@Suite(.datadogTesting) struct Benchmark {
//    @Test func testBenchmark() {
//        print("Benchmark")
//    }
//}

//@Suite(.datadogTesting) struct Flaky {
//    @Test func testFlaky() {
//        print("Flaky")
//        #expect((0...2).randomElement() == 0)
//    }
//}

@Suite(.datadogTesting) struct STNetworkIntegration {
    @Test func networkIntegration() async throws {
        let url = URL(string: "https://github.com/DataDog/dd-sdk-swift-testing")!
        let (_, _) = try await URLSession.shared.data(from: url)
    }
}


@Suite(.datadogTesting) struct STCrash {
    @Test func crash() {
        let array: [Int] = [1]
        #expect(array[1] == 1)
    }
    
    @Test func noCrash() {
        let array: [Int] = [1]
        #expect(array[0] == 1)
    }
}
