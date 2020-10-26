/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import DatadogExporter
import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

enum DDHeaders: String, CaseIterable {
    case traceIDField = "x-datadog-trace-id"
    case parentSpanIDField = "x-datadog-parent-id"
}

internal class DDTracer {
    let tracerSdk: TracerSdk
    let env = DDEnvironmentValues()
    var spanProcessor: SpanProcessor
    let datadogExporter: DatadogExporter

    init() {
        tracerSdk = OpenTelemetrySDK.instance.tracerProvider.get(instrumentationName: "hq.datadog.testing", instrumentationVersion: "0.1.0") as! TracerSdk

        let exporterConfiguration = ExporterConfiguration(
            serviceName: env.ddService ?? ProcessInfo.processInfo.processName,
            resource: "Resource",
            applicationName: "SimpleExporter",
            applicationVersion: "0.0.1",
            environment: env.ddEnvironment ?? "ci",
            clientToken: env.ddClientToken ?? "",
            endpoint: Endpoint.us,
            uploadCondition: { true },
            performancePreset: .instantDataDelivery
        )

        datadogExporter = try! DatadogExporter(config: exporterConfiguration)
        spanProcessor = SimpleSpanProcessor(spanExporter: datadogExporter)

        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(spanProcessor)
    }

    func startSpan(name: String, attributes: [String: String], date: Date? = nil) -> RecordEventsReadableSpan {
        let spanBuilder = tracerSdk.spanBuilder(spanName: name)
        attributes.forEach {
            spanBuilder.setAttribute(key: $0.key, value: $0.value)
        }
        if let startTimestamp = date {
            spanBuilder.setStartTimestamp(timestamp: startTimestamp)
        }
        let span = spanBuilder.startSpan() as! RecordEventsReadableSpan
        _ = tracerSdk.withSpan(span)
        return span
    }

    /// This method is called form the crash reporter if the previous run crashed while running a test.Then it recreates the span with the previous information
    /// and adds the error status and information
    @discardableResult func createSpanFromCrash(spanData: SimpleSpanData, crashDate: Date?, errorType: String, errorMessage: String, errorStack: String) -> RecordEventsReadableSpan {
        let spanName = spanData.name
        let traceId = TraceId(idHi: spanData.traceIdHi, idLo: spanData.traceIdLo)
        let spanId = SpanId(id: spanData.spanId)
        let startTime = spanData.startEpochNanos
        let spanContext = SpanContext.create(traceId: traceId,
                                             spanId: spanId,
                                             traceFlags: TraceFlags().settingIsSampled(true),
                                             traceState: TraceState())
        var attributes = AttributesWithCapacity(capacity: tracerSdk.sharedState.activeTraceConfig.maxNumberOfAttributes)
        spanData.stringAttributes.forEach {
            attributes.updateValue(value: AttributeValue.string($0.value), forKey: $0.key)
        }

        attributes.updateValue(value: AttributeValue.string(DDTestingTags.statusFail), forKey: DDTestingTags.testStatus)
        attributes.updateValue(value: AttributeValue.string(errorType), forKey: DDTags.errorType)
        attributes.updateValue(value: AttributeValue.string(errorMessage), forKey: DDTags.errorMessage)
        attributes.updateValue(value: AttributeValue.string(errorStack), forKey: DDTags.errorStack)

        let span = RecordEventsReadableSpan.startSpan(context: spanContext,
                                                      name: spanName,
                                                      instrumentationLibraryInfo: tracerSdk.instrumentationLibraryInfo,
                                                      kind: .internal,
                                                      parentSpanId: nil,
                                                      hasRemoteParent: false,
                                                      traceConfig: tracerSdk.sharedState.activeTraceConfig,
                                                      spanProcessor: tracerSdk.sharedState.activeSpanProcessor,
                                                      clock: MonotonicClock(clock: tracerSdk.sharedState.clock),
                                                      resource: Resource(),
                                                      attributes: attributes,
                                                      links: [Link](),
                                                      totalRecordedLinks: 0,
                                                      startEpochNanos: startTime)

        var crashTimeStamp = spanData.startEpochNanos + 1
        if let timeInterval = crashDate?.timeIntervalSince1970 {
            crashTimeStamp = max(crashTimeStamp, UInt64(timeInterval * 1_000_000_000))
        }
        span.status = .internalError
        span.end(endOptions: EndSpanOptions(timestamp: crashTimeStamp))
        self.flush()
        return span
    }

    func logString(string: String, date: Date? = nil) {
        let activeSpan = tracerSdk.currentSpan ?? DDTestMonitor.instance?.testObserver.activeTestSpan
        activeSpan?.addEvent(name: "logString", attributes: ["message": AttributeValue.string(string)], timestamp: date ?? Date())
    }

    func logString(string: String, timeIntervalSinceSpanStart: Double) {
        guard let activeSpan = (tracerSdk.currentSpan as? RecordEventsReadableSpan) ??
                DDTestMonitor.instance?.testObserver.activeTestSpan else {
            return
        }
        let eventNanos = activeSpan.startEpochNanos + UInt64(timeIntervalSinceSpanStart * 1000000000)
        let timedEvent = TimedEvent(name: "logString",
                                    epochNanos: eventNanos,
                                    attributes: ["message": AttributeValue.string(string)])
        activeSpan.addEvent(event: timedEvent)
    }

    func flush() {
        spanProcessor.forceFlush()
    }

    func tracePropagationHTTPHeaders() -> [String: String] {
        var headers = [String: String]()

        struct HeaderSetter: Setter {
            func set(carrier: inout [String: String], key: String, value: String) {
                carrier[key] = value
            }
        }

        guard let currentSpan = tracerSdk.currentSpan else {
            return headers
        }
        tracerSdk.textFormat.inject(spanContext: currentSpan.context, carrier: &headers, setter: HeaderSetter())

        headers[DDHeaders.traceIDField.rawValue] = String(format: "%016llx", currentSpan.context.traceId.rawLowerLong)
        headers[DDHeaders.parentSpanIDField.rawValue] = currentSpan.context.spanId.hexString

        return headers
    }

    func endpointURLs() -> Set<String> {
        return datadogExporter.endpointURLs()
    }
}
