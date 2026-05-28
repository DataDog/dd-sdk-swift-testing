/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import OpenTelemetryApi
@testable import OpenTelemetrySdk
import XCTest

final class TestSpanTests: XCTestCase {
    func testSession_doesNotLeakDuplicatedKeysIntoMeta() throws {
        let span = makeSpan(spanId: SpanId(id: 0x1111), attributes: [
            "type": .string("test_session_end"),
            "test_session_id": .string(SpanId(id: 0x1111).hexString),
            "resource": .string("MySession"),
            "test.command": .string("xcodebuild test"),
            "test.status": .string("pass"),
        ])

        let json = try encode(TestSpan(spanData: span, spanType: .sessionEnd))
        let meta = try XCTUnwrap(json["meta"] as? [String: String])

        XCTAssertEqual(json["test_session_id"] as? UInt64, 0x1111)
        XCTAssertEqual(json["resource"] as? String, "MySession")
        XCTAssertEqual(json["type"] as? String, "test_session_end")
        XCTAssertNil(meta["type"], "top-level `type` shouldn't be duplicated in meta")
        XCTAssertNil(meta["test_session_id"], "top-level `test_session_id` shouldn't be duplicated in meta")
        XCTAssertNil(meta["resource"], "top-level `resource` shouldn't be duplicated in meta")
        XCTAssertEqual(meta["test.command"], "xcodebuild test")
        XCTAssertEqual(meta["test.status"], "pass")
    }

    func testModule_doesNotLeakDuplicatedKeysIntoMeta() throws {
        let span = makeSpan(spanId: SpanId(id: 0x2222), attributes: [
            "type": .string("test_module_end"),
            "test_session_id": .string(SpanId(id: 0x1111).hexString),
            "test_module_id": .string(SpanId(id: 0x2222).hexString),
            "resource": .string("MyModule"),
            "test.module": .string("MyModule"),
        ])

        let json = try encode(TestSpan(spanData: span, spanType: .moduleEnd))
        let meta = try XCTUnwrap(json["meta"] as? [String: String])

        XCTAssertEqual(json["test_session_id"] as? UInt64, 0x1111)
        XCTAssertEqual(json["test_module_id"] as? UInt64, 0x2222)
        XCTAssertEqual(json["type"] as? String, "test_module_end")
        XCTAssertNil(meta["type"])
        XCTAssertNil(meta["test_session_id"])
        XCTAssertNil(meta["test_module_id"])
        XCTAssertNil(meta["resource"])
        XCTAssertEqual(meta["test.module"], "MyModule")
    }

    func testSuite_doesNotLeakDuplicatedKeysIntoMeta() throws {
        let span = makeSpan(spanId: SpanId(id: 0x3333), attributes: [
            "type": .string("test_suite_end"),
            "test_session_id": .string(SpanId(id: 0x1111).hexString),
            "test_module_id": .string(SpanId(id: 0x2222).hexString),
            "test_suite_id": .string(SpanId(id: 0x3333).hexString),
            "resource": .string("MySuite"),
            "test.suite": .string("MySuite"),
        ])

        let json = try encode(TestSpan(spanData: span, spanType: .suiteEnd))
        let meta = try XCTUnwrap(json["meta"] as? [String: String])

        XCTAssertEqual(json["test_session_id"] as? UInt64, 0x1111)
        XCTAssertEqual(json["test_module_id"] as? UInt64, 0x2222)
        XCTAssertEqual(json["test_suite_id"] as? UInt64, 0x3333)
        XCTAssertEqual(json["type"] as? String, "test_suite_end")
        XCTAssertNil(meta["type"])
        XCTAssertNil(meta["test_session_id"])
        XCTAssertNil(meta["test_module_id"])
        XCTAssertNil(meta["test_suite_id"])
        XCTAssertNil(meta["resource"])
        XCTAssertEqual(meta["test.suite"], "MySuite")
    }

    func testTest_encodesTraceAndCorrelationFields() throws {
        var resource = Resource()
        resource.service = "service"
        resource.applicationVersion = "1.2.3"

        let traceId = TraceId.random()
        let span = SpanData(traceId: traceId,
                            spanId: SpanId(id: 0x4444),
                            traceFlags: TraceFlags(),
                            traceState: TraceState(),
                            parentSpanId: nil,
                            resource: resource,
                            instrumentationScope: InstrumentationScopeInfo(),
                            name: "MyFramework.test",
                            kind: .internal,
                            startTime: Date(timeIntervalSinceReferenceDate: 1000),
                            attributes: [
                                "type": .string("test"),
                                "resource": .string("MySuite.testCase"),
                                "test_session_id": .string(SpanId(id: 0x1111).hexString),
                                "test_module_id": .string(SpanId(id: 0x2222).hexString),
                                "test_suite_id": .string(SpanId(id: 0x3333).hexString),
                                "itr_correlation_id": .string("itr-corr-1"),
                                "test.status": .string("pass"),
                                "test.run_count": .int(3),
                            ],
                            endTime: Date(timeIntervalSinceReferenceDate: 1001),
                            hasRemoteParent: false)

        let json = try encode(TestSpan(spanData: span, spanType: .test))
        let meta = try XCTUnwrap(json["meta"] as? [String: String])
        let metrics = try XCTUnwrap(json["metrics"] as? [String: Double])

        XCTAssertEqual(json["trace_id"] as? UInt64, traceId.rawLowerLong)
        XCTAssertEqual(json["span_id"] as? UInt64, 0x4444)
        XCTAssertEqual(json["parent_id"] as? UInt64, 0)
        XCTAssertEqual(json["test_session_id"] as? UInt64, 0x1111)
        XCTAssertEqual(json["test_module_id"] as? UInt64, 0x2222)
        XCTAssertEqual(json["test_suite_id"] as? UInt64, 0x3333)
        XCTAssertEqual(json["itr_correlation_id"] as? String, "itr-corr-1")
        XCTAssertEqual(json["type"] as? String, "test")
        XCTAssertEqual(json["resource"] as? String, "MySuite.testCase")

        XCTAssertNil(meta["resource"], "top-level `resource` shouldn't be duplicated in meta")
        XCTAssertNil(meta["type"], "top-level `type` shouldn't be duplicated in meta")
        XCTAssertEqual(meta["test.status"], "pass")
        // Default meta the test path always sets.
        XCTAssertEqual(meta["_dd.source"], "ios")
        XCTAssertEqual(meta["version"], "1.2.3")
        // ITR correlation id is top-level only, never in meta.
        XCTAssertNil(meta["itr_correlation_id"])
        // Numeric custom attributes land in metrics.
        XCTAssertEqual(metrics["test.run_count"], 3)
        // Root span marker.
        XCTAssertEqual(metrics["_top_level"], 1)
    }

    func testTest_truncatesMetaStringValuesAndPreservesMetricsAndTopLevelIds() throws {
        let longValue = String(repeating: "a", count: maxMetaStringValueLength + 1)
        let exactValue = String(repeating: "b", count: maxMetaStringValueLength)
        let span = SpanData(traceId: TraceId.random(),
                            spanId: SpanId(id: 0x7777),
                            traceFlags: TraceFlags(),
                            traceState: TraceState(),
                            parentSpanId: nil,
                            resource: Resource(),
                            instrumentationScope: InstrumentationScopeInfo(),
                            name: "MyFramework.test",
                            kind: .internal,
                            startTime: Date(timeIntervalSinceReferenceDate: 1000),
                            attributes: [
                                "type": .string("test"),
                                "test_session_id": .string(SpanId(id: 0x1111).hexString),
                                "test_module_id": .string(SpanId(id: 0x2222).hexString),
                                "test_suite_id": .string(SpanId(id: 0x3333).hexString),
                                "custom.long": .string(longValue),
                                "custom.exact": .string(exactValue),
                                "custom.metric": .int(42),
                            ],
                            endTime: Date(timeIntervalSinceReferenceDate: 1001),
                            hasRemoteParent: false)

        let json = try encode(TestSpan(spanData: span, spanType: .test))
        let meta = try XCTUnwrap(json["meta"] as? [String: String])
        let metrics = try XCTUnwrap(json["metrics"] as? [String: Double])

        XCTAssertEqual(meta["custom.long"], String(longValue.prefix(maxMetaStringValueLength)))
        XCTAssertEqual(meta["custom.long"]?.count, maxMetaStringValueLength)
        XCTAssertEqual(meta["custom.exact"], exactValue)
        XCTAssertEqual(metrics["custom.metric"], 42)
        XCTAssertNil(meta["test_session_id"])
        XCTAssertNil(meta["test_module_id"])
        XCTAssertNil(meta["test_suite_id"])
        XCTAssertEqual(json["test_session_id"] as? UInt64, 0x1111)
        XCTAssertEqual(json["test_module_id"] as? UInt64, 0x2222)
        XCTAssertEqual(json["test_suite_id"] as? UInt64, 0x3333)
    }

    func testSession_truncatesMetaStringValues() throws {
        let longValue = String(repeating: "s", count: maxMetaStringValueLength + 1)
        let span = makeSpan(spanId: SpanId(id: 0x8888), attributes: [
            "type": .string("test_session_end"),
            "test_session_id": .string(SpanId(id: 0x8888).hexString),
            "custom.long": .string(longValue),
        ])

        let json = try encode(TestSpan(spanData: span, spanType: .sessionEnd))
        let meta = try XCTUnwrap(json["meta"] as? [String: String])

        XCTAssertEqual(meta["custom.long"], String(longValue.prefix(maxMetaStringValueLength)))
        XCTAssertEqual(meta["custom.long"]?.count, maxMetaStringValueLength)
        XCTAssertNil(meta["test_session_id"])
        XCTAssertEqual(json["test_session_id"] as? UInt64, 0x8888)
    }

    func testTest_omitsTopLevelMetric_whenSpanHasParent() throws {
        var resource = Resource()
        resource.service = "service"
        let span = SpanData(traceId: TraceId.random(),
                            spanId: SpanId(id: 0x5555),
                            traceFlags: TraceFlags(),
                            traceState: TraceState(),
                            parentSpanId: SpanId(id: 0x9999),
                            resource: resource,
                            instrumentationScope: InstrumentationScopeInfo(),
                            name: "MyFramework.test",
                            kind: .internal,
                            startTime: Date(timeIntervalSinceReferenceDate: 1000),
                            attributes: [
                                "type": .string("test"),
                                "test_session_id": .string(SpanId(id: 0x1111).hexString),
                                "test_module_id": .string(SpanId(id: 0x2222).hexString),
                                "test_suite_id": .string(SpanId(id: 0x3333).hexString),
                            ],
                            endTime: Date(timeIntervalSinceReferenceDate: 1001),
                            hasRemoteParent: false)

        let json = try encode(TestSpan(spanData: span, spanType: .test))
        let metrics = try XCTUnwrap(json["metrics"] as? [String: Double])
        XCTAssertEqual(json["parent_id"] as? UInt64, 0x9999)
        XCTAssertNil(metrics["_top_level"], "_top_level is only set for root spans")
    }

    func testTest_sanitizesOverDeepAttributeKeys() throws {
        var resource = Resource()
        resource.service = "service"
        let deepKey = (0..<12).map { "level\($0)" }.joined(separator: ".")
        let span = SpanData(traceId: TraceId.random(),
                            spanId: SpanId(id: 0x6666),
                            traceFlags: TraceFlags(),
                            traceState: TraceState(),
                            parentSpanId: nil,
                            resource: resource,
                            instrumentationScope: InstrumentationScopeInfo(),
                            name: "MyFramework.test",
                            kind: .internal,
                            startTime: Date(timeIntervalSinceReferenceDate: 1000),
                            attributes: [
                                "type": .string("test"),
                                "test_session_id": .string(SpanId(id: 0x1).hexString),
                                "test_module_id": .string(SpanId(id: 0x2).hexString),
                                "test_suite_id": .string(SpanId(id: 0x3).hexString),
                                deepKey: .string("value"),
                            ],
                            endTime: Date(timeIntervalSinceReferenceDate: 1001),
                            hasRemoteParent: false)

        let json = try encode(TestSpan(spanData: span, spanType: .test))
        let meta = try XCTUnwrap(json["meta"] as? [String: String])
        XCTAssertNil(meta[deepKey], "over-deep key should be re-escaped")
        // AttributesSanitizer keeps the first 9 dots and replaces the
        // 10th-onward with `_`.
        XCTAssertEqual(meta["level0.level1.level2.level3.level4.level5.level6.level7.level8.level9_level10_level11"],
                       "value")
    }

    // MARK: - helpers

    private func makeSpan(spanId: SpanId, attributes: [String: AttributeValue]) -> SpanData {
        var resource = Resource()
        resource.service = "service"
        return SpanData(traceId: TraceId(),
                        spanId: spanId,
                        traceFlags: TraceFlags(),
                        traceState: TraceState(),
                        resource: resource,
                        instrumentationScope: InstrumentationScopeInfo(),
                        name: "lifecycle",
                        kind: .internal,
                        startTime: Date(timeIntervalSinceReferenceDate: 1000),
                        attributes: attributes,
                        endTime: Date(timeIntervalSinceReferenceDate: 1001),
                        hasRemoteParent: false)
    }

    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
