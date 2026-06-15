/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import OpenTelemetryApi
@testable import OpenTelemetrySdk
import XCTest

class DDTracerTests: XCTestCase {
    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        setEnv(env: [:])
    }

    override func tearDown() {
        XCTAssertNil(DDTracer.activeSpan)
        DDTestMonitor._env_recreate()
        OpenTelemetry.registerTracerProvider(tracerProvider: DefaultTracerProvider.instance)
    }

    func testWhenCalledStartSpanAttributes_spanIsCreatedWithAttributes() {
        let tracer = DDTracer()
        let attributes = ["myKey": AttributeValue.string("myValue")]
        let spanName = "myName"

        let spanData = tracer.withActiveSpan(name: spanName, attributes: attributes) { span in
             span.toSpanData()
        }
        XCTAssertEqual(spanData.name, spanName)
        XCTAssertEqual(spanData.attributes.count, 1)
        XCTAssertEqual(spanData.attributes["myKey"]?.description, "myValue")
    }

    func testTracePropagationHTTPHeadersCalledWithAnActiveSpan_returnTraceIdAndSpanId() {
        let tracer = DDTracer()
        let spanName = "myName"

        let (spanData, headers) = tracer.withActiveSpan(name: spanName, attributes: [:]) { span in
            (span.toSpanData(), tracer.tracePropagationHTTPHeaders())
        }
        XCTAssertEqual(headers[DDHeaders.traceIDField.rawValue], String(spanData.traceId.rawLowerLong))
        XCTAssertEqual(headers[DDHeaders.parentSpanIDField.rawValue], String(spanData.spanId.rawValue))
    }

    func testTracePropagationHTTPHeadersCalledWithNoActiveSpan_returnsEmpty() {
        let tracer = DDTracer()
        let headers = tracer.tracePropagationHTTPHeaders()

        XCTAssertEqual(headers.count, 0)
        print(headers)
    }

    func testCreateSpanFromCrash() {
        let startTime = Date(timeIntervalSinceReferenceDate: 33)
        let simpleSpan = SimpleSpanData(traceIdHi: 1, traceIdLo: 2, spanId: 3, name: "name",
                                        startTime: startTime, stringAttributes: [:],
                                        sessionStartTime: startTime, moduleStartTime: startTime)
        let crashDate: Date? = nil
        let errorType = "errorType"
        let errorMessage = "errorMessage"
        let errorStack = "errorStack"

        let tracer = DDTracer()
        let span = tracer.createSpanFromCrash(spanData: simpleSpan,
                                              crashDate: crashDate,
                                              error: TestError(type: errorType,
                                                               message: errorMessage,
                                                               stack: errorStack))
        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.name, "name")
        XCTAssertEqual(spanData.traceId, TraceId(idHi: 1, idLo: 2))
        XCTAssertEqual(spanData.spanId, SpanId(id: 3))
        XCTAssertEqual(spanData.attributes[DDTestTags.testStatus], AttributeValue.string(DDTagValues.statusFail))
        XCTAssertEqual(spanData.status, Status.error(description: errorMessage))
        XCTAssertEqual(spanData.attributes[DDTags.errorType], AttributeValue.string(errorType))
        XCTAssertEqual(spanData.attributes[DDTags.errorMessage], AttributeValue.string(errorMessage))
        XCTAssertEqual(spanData.attributes[DDTags.errorStack], AttributeValue.string(errorStack))
        XCTAssertEqual(spanData.endTime, spanData.startTime.addingTimeInterval(TimeInterval.fromMicroseconds(1)))
    }

    func testAddingTagsWithOpenTelemetry() {
        let tracer = DDTracer()
        let spanName = "myName"

        let spanData = tracer.withActiveSpan(name: spanName, attributes: [:]) { span in
            // Get active Span with OpentelemetryApi and set tags
            OpenTelemetry.instance.contextProvider.activeSpan?.setAttribute(key: "OTTag", value: "OTValue")

            return span.toSpanData()
        }
        XCTAssertEqual(spanData.attributes["OTTag"], AttributeValue.string("OTValue"))
    }

    func testEndpointIsUSByDefault() {
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.datadoghq.com/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-datadoghq.com/api/v2/logs"))
    }

    func testEndpointChangeToUS() {
        setEnv(env: ["DD_SITE": "US"])

        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.datadoghq.com/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-datadoghq.com/api/v2/logs"))
    }

    func testEndpointChangeToUS3() {
        setEnv(env: ["DD_SITE": "us3"])

        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.us3.datadoghq.com/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-us3-datadoghq.com/api/v2/logs"))
    }

    func testEndpointChangeToUS5() {
        setEnv(env: ["DD_SITE": "us5"])
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.us5.datadoghq.com/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-us5-datadoghq.com/api/v2/logs"))
    }

    func testEndpointChangeToEU() {
        setEnv(env: ["DD_SITE": "eu"])
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.datadoghq.eu/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://mobile-http-intake.logs.datadoghq.eu/api/v2/logs"))
    }
    
    func testEndpointChangeToAP1() {
        setEnv(env: ["DD_SITE": "ap1"])
        let tracer = DDTracer()
        XCTAssertTrue(tracer.endpointURLs().contains("https://citestcycle-intake.ap1.datadoghq.com/api/v2/citestcycle"))
        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-ap1-datadoghq.com/api/v2/logs"))
    }

//    func testEndpointChangeToGov() {
//        DDEnvironmentValues.environment["DD_SITE"] = "GOV"
//        resetEnvironmentVariables()
//
//        let tracer = DDTracer()
//        XCTAssertTrue(tracer.endpointURLs().contains("https://trace.browser-intake-ddog-gov.com/api/v2/spans"))
//        XCTAssertTrue(tracer.endpointURLs().contains("https://logs.browser-intake-ddog-gov.com/api/v2/logs"))
//        DDEnvironmentValues.environment["DD_SITE"] = nil
//    }

    func testEnvironmentContext() {
        let testTraceId = TraceId(fromHexString: "ff000000000000000000000000000041")
        let testSpanId = SpanId(fromHexString: "ff00000000000042")
        
        setEnv(env: ["ENVIRONMENT_TRACER_TRACEID": testTraceId.hexString,
                     "ENVIRONMENT_TRACER_SPANID": testSpanId.hexString])

        let tracer = DDTracer()

        let propagationContext = tracer.propagationContext
        XCTAssertEqual(propagationContext?.traceId, testTraceId)
        XCTAssertEqual(propagationContext?.spanId, testSpanId)
    }

    func testCreateSpanFromCrashAndEnvironmentContext() {
        let testTraceId = TraceId(fromHexString: "ff000000000000000000000000000041")
        let testSpanId = SpanId(fromHexString: "ff00000000000042")
        
        setEnv(env: ["ENVIRONMENT_TRACER_TRACEID": testTraceId.hexString,
                     "ENVIRONMENT_TRACER_SPANID": testSpanId.hexString])

        let startTime = Date(timeIntervalSinceReferenceDate: 33)
        let simpleSpan = SimpleSpanData(traceIdHi: testTraceId.idHi, traceIdLo: testTraceId.idLo,
                                        spanId: 3, name: "name", startTime: startTime,
                                        stringAttributes: [:], sessionStartTime: startTime, moduleStartTime: startTime)
        let crashDate: Date? = nil
        let errorType = "errorType"
        let errorMessage = "errorMessage"
        let errorStack = "errorStack"

        let tracer = DDTracer()
        let span = tracer.createSpanFromCrash(spanData: simpleSpan,
                                              crashDate: crashDate,
                                              error: TestError(type: errorType,
                                                               message: errorMessage,
                                                               stack: errorStack))
        let spanData = span.toSpanData()

        XCTAssertEqual(spanData.name, "name")
        XCTAssertEqual(spanData.traceId, testTraceId)
        XCTAssertEqual(spanData.attributes[DDTestTags.testStatus], AttributeValue.string(DDTagValues.statusFail))
        XCTAssertEqual(spanData.status, Status.error(description: errorMessage))
        XCTAssertEqual(spanData.attributes[DDTags.errorType], AttributeValue.string(errorType))
        XCTAssertEqual(spanData.attributes[DDTags.errorMessage], AttributeValue.string(errorMessage))
        XCTAssertEqual(spanData.attributes[DDTags.errorStack], AttributeValue.string(errorStack))
        XCTAssertEqual(spanData.endTime, spanData.startTime.addingTimeInterval(TimeInterval.fromMicroseconds(1)))
    }

    /// When the host app is launched from a UI test there's no active span,
    /// but the harness passes a launch trace/span pair via env. `logString`
    /// must emit the captured text as a `LogRecord` carrying that launch
    /// context — it must NOT synthesize an aux span (the old implementation
    /// did, but that polluted the trace stream).
    func testLogStringAppUI() throws {
        let testTraceId = TraceId(fromHexString: "ff000000000000000000000000000041")
        let testSpanId = SpanId(fromHexString: "ff00000000000042")

        setEnv(env: ["ENVIRONMENT_TRACER_TRACEID": testTraceId.hexString,
                     "ENVIRONMENT_TRACER_SPANID": testSpanId.hexString])

        let logExporter = InMemoryLogRecordExporter()
        let tracer = DDTracer(logRecordExporter: logExporter)
        let testSpanProcessor = SpySpanProcessor()
        tracer.tracerProviderSdk.addSpanProcessor(testSpanProcessor)

        let timestamp = Date(timeIntervalSince1970: 1212)
        tracer.logString(string: "Hello World", date: timestamp)
        tracer.flush()

        XCTAssertNil(testSpanProcessor.lastProcessedSpan,
                     "no span should be produced — the message must go out as a LogRecord")

        let records = logExporter.getFinishedLogRecords()
        XCTAssertEqual(records.count, 1)
        let record = records[0]
        XCTAssertEqual(record.body?.description, "Hello World")
        XCTAssertEqual(record.severity, .info)
        XCTAssertEqual(record.timestamp, timestamp)
        XCTAssertEqual(record.spanContext?.traceId, testTraceId,
                       "launch traceId from env must be propagated onto the log record")
        XCTAssertEqual(record.spanContext?.spanId, testSpanId,
                       "launch spanId from env must be propagated onto the log record")
    }

    func testEnvironmentConstantPropagation() {
        let tracer = DDTracer()
        let spanName = "myName"

        let (spanData, environmentValues) = tracer.withActiveSpan(name: spanName, attributes: [:]) { span in
            (span.toSpanData(), tracer.environmentPropagationHTTPHeaders())
        }
        
        XCTAssertNotNil(environmentValues["TRACEPARENT"])
        XCTAssert(environmentValues["TRACEPARENT"]?.contains(spanData.traceId.hexString) ?? false)
        XCTAssertTrue(environmentValues["TRACEPARENT"]?.contains(spanData.spanId.hexString) ?? false)

        XCTAssertNotNil(environmentValues[DDHeaders.traceIDField.rawValue])
        XCTAssertEqual(environmentValues[DDHeaders.traceIDField.rawValue], String(spanData.traceId.rawLowerLong))
        XCTAssertNotNil(environmentValues[DDHeaders.parentSpanIDField.rawValue])
        XCTAssertEqual(environmentValues[DDHeaders.parentSpanIDField.rawValue], String(spanData.spanId.rawValue))
        XCTAssertNotNil(environmentValues[EnvironmentKey.testExecutionId.rawValue])
        XCTAssertEqual(environmentValues[EnvironmentKey.testExecutionId.rawValue],
                       String(spanData.traceId.rawLowerLong))
    }

    func testWhenNoContextActivePropagationAreEmpty() {
        let tracer = DDTracer()
        let environmentValues = tracer.environmentPropagationHTTPHeaders()
        let datadogHeaders = tracer.datadogHeaders(forContext: nil)

        XCTAssertTrue(environmentValues.isEmpty)
        XCTAssertTrue(datadogHeaders.isEmpty)
    }

    func testEnvironmentConstantPropagationWithRUMIntegrationDisabled() {
        setEnv(env: ["DD_DISABLE_SDKIOS_INTEGRATION": "1"])

        let tracer = DDTracer()
        let spanName = "myName"

        let (spanData, environmentValues) = tracer.withActiveSpan(name: spanName, attributes: [:]) { span in
            (span.toSpanData(), tracer.environmentPropagationHTTPHeaders())
        }
        XCTAssertNotNil(environmentValues["TRACEPARENT"])
        XCTAssert(environmentValues["TRACEPARENT"]?.contains(spanData.traceId.hexString) ?? false)
        XCTAssertTrue(environmentValues["TRACEPARENT"]?.contains(spanData.spanId.hexString) ?? false)

        XCTAssertNil(environmentValues[DDHeaders.traceIDField.rawValue])
        XCTAssertNil(environmentValues[DDHeaders.parentSpanIDField.rawValue])
    }
    
    // MARK: - Product-under-test version resolution

    private func info(_ path: String, id: String? = nil, name: String, version: String?) -> Bundle.UnderTestInfo {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return Bundle.UnderTestInfo(directory: url.deletingLastPathComponent().path,
                                    path: url.path, identifier: id, name: name, version: version)
    }

    /// App-hosted (or UI) tests: `Bundle.main` is the real `.app`, so it is the product.
    func testProductUnderTest_appHostBundleIsTheProduct() {
        let main = info("/Build/Debug/MyApp.app", id: "com.acme.MyApp", name: "MyApp", version: "3.2.1")
        let test = info("/Build/Debug/MyAppTests.xctest", name: "MyAppTests", version: nil)
        let (name, version) = Bundle.productUnderTest(main: main, test: test, frameworks: [], schemeName: "MyApp")
        XCTAssertEqual(name, "com.acme.MyApp")
        XCTAssertEqual(version, "3.2.1")
    }

    /// Host-less `.xctest`: a dynamic framework named after the scheme sits next
    /// to the test bundle. It wins over other co-located frameworks.
    func testProductUnderTest_siblingFrameworkMatchedByScheme() {
        let main = info("/Xcode/Agents/xctest", name: "xctest", version: nil)
        let test = info("/Build/Debug/MyLibTests.xctest", name: "MyLibTests", version: nil)
        let sdk = info("/Build/Debug/DatadogSDKTesting.framework", id: "com.dd.sdk", name: "DatadogSDKTesting", version: "9.9.9")
        let lib = info("/Build/Debug/MyLib.framework", id: "com.acme.MyLib", name: "MyLib", version: "1.4.0")
        let (name, version) = Bundle.productUnderTest(main: main, test: test, frameworks: [sdk, lib], schemeName: "MyLib")
        XCTAssertEqual(name, "com.acme.MyLib")
        XCTAssertEqual(version, "1.4.0")
    }

    /// A framework matched by name but in an unrelated directory must be ignored.
    func testProductUnderTest_frameworkInOtherDirectoryIgnored() {
        let main = info("/Xcode/Agents/xctest", name: "xctest", version: nil)
        let test = info("/Build/Debug/MyLibTests.xctest", name: "MyLibTests", version: "5.0")
        let strayLib = info("/somewhere/else/MyLib.framework", name: "MyLib", version: "1.4.0")
        let (_, version) = Bundle.productUnderTest(main: main, test: test, frameworks: [strayLib], schemeName: "MyLib")
        XCTAssertEqual(version, "5.0", "Should fall back to the xctest version, not the unrelated framework")
    }

    /// A framework embedded inside the `.xctest` bundle is also accepted.
    func testProductUnderTest_frameworkEmbeddedInsideXctest() {
        let main = info("/Xcode/Agents/xctest", name: "xctest", version: nil)
        let test = info("/Build/Debug/MyLibTests.xctest", name: "MyLibTests", version: nil)
        let lib = info("/Build/Debug/MyLibTests.xctest/Frameworks/MyLib.framework", name: "MyLib", version: "2.0.0")
        let (_, version) = Bundle.productUnderTest(main: main, test: test, frameworks: [lib], schemeName: "MyLib")
        XCTAssertEqual(version, "2.0.0")
    }

    /// No product framework (e.g. `IntegrationTests-UnitTests`, or static/SPM merged
    /// products): report the `.xctest` bundle version.
    func testProductUnderTest_fallsBackToXctestVersion() {
        let main = info("/Xcode/Agents/xctest", name: "xctest", version: nil)
        let test = info("/Build/Debug/MyLibTests.xctest", id: "com.acme.MyLibTests", name: "MyLibTests", version: "7.7.7")
        let (name, version) = Bundle.productUnderTest(main: main, test: test, frameworks: [], schemeName: "MyLib")
        XCTAssertEqual(name, "com.acme.MyLibTests")
        XCTAssertEqual(version, "7.7.7")
    }

    /// A matched framework without a version still falls through to the xctest version.
    func testProductUnderTest_versionlessFrameworkFallsBackToXctest() {
        let main = info("/Xcode/Agents/xctest", name: "xctest", version: nil)
        let test = info("/Build/Debug/MyLibTests.xctest", name: "MyLibTests", version: "7.7.7")
        let lib = info("/Build/Debug/MyLib.framework", name: "MyLib", version: nil)
        let (_, version) = Bundle.productUnderTest(main: main, test: test, frameworks: [lib], schemeName: "MyLib")
        XCTAssertEqual(version, "7.7.7")
    }

    /// Nothing resolvable (no scheme, versionless xctest): unknown.
    func testProductUnderTest_unknownWhenNothingResolvable() {
        let main = info("/Xcode/Agents/xctest", name: "xctest", version: nil)
        let test = info("/Build/Debug/MyLibTests.xctest", name: "MyLibTests", version: nil)
        let (_, version) = Bundle.productUnderTest(main: main, test: test, frameworks: [], schemeName: nil)
        XCTAssertEqual(version, "<unknown>")
    }

    /// The `DD_VERSION` override wins over every derived source.
    func testProductUnderTest_versionOverrideWins() {
        let main = info("/Build/Debug/MyApp.app", id: "com.acme.MyApp", name: "MyApp", version: "3.2.1")
        let test = info("/Build/Debug/MyAppTests.xctest", name: "MyAppTests", version: "9.9")
        let (name, version) = Bundle.productUnderTest(main: main, test: test, frameworks: [],
                                                      schemeName: "MyApp", versionOverride: "42.0.0")
        XCTAssertEqual(name, "com.acme.MyApp", "Override affects only the version, not the name")
        XCTAssertEqual(version, "42.0.0")
    }

    /// `DD_VERSION` flows from configuration into the resolved tracer version.
    func testProductUnderTest_ddVersionFromConfig() {
        let config = Config(env: ProcessEnvironmentReader(environment: ["DD_VERSION": "12.3.4"]))
        XCTAssertEqual(config.applicationVersion, "12.3.4")
    }

    private func setEnv(env: [String: String]) {
        var env = env
        env["DD_API_KEY"] = "fakeToken"
        env["DD_DISABLE_TEST_INSTRUMENTING"] = "1"
        DDTestMonitor._env_recreate(env: env)
    }
}
