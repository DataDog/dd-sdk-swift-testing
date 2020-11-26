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
    var launchSpanContext: SpanContext?

    var activeSpan: RecordEventsReadableSpan? {
        return tracerSdk.currentSpan as? RecordEventsReadableSpan ??
            DDTestMonitor.instance?.testObserver?.currentTestSpan
    }

    var isBinaryUnderUITesting: Bool {
        return launchSpanContext != nil
    }

    init() {
        if let envTraceId = ProcessInfo.processInfo.environment["ENVIRONMENT_TRACER_TRACEID"],
            let envSpanId = ProcessInfo.processInfo.environment["ENVIRONMENT_TRACER_SPANID"] {
            let launchTraceId = TraceId(fromHexString: envTraceId)
            let launchSpanId = SpanId(fromHexString: envSpanId)
            launchSpanContext = SpanContext.create(traceId: launchTraceId,
                                                   spanId: launchSpanId,
                                                   traceFlags: TraceFlags().settingIsSampled(false),
                                                   traceState: TraceState())
        }

        tracerSdk = OpenTelemetrySDK.instance.tracerProvider.get(instrumentationName: "com.datadoghq.testing", instrumentationVersion: "0.2.0") as! TracerSdk

        let exporterConfiguration = ExporterConfiguration(
            serviceName: env.ddService ?? ProcessInfo.processInfo.processName,
            resource: "Resource",
            applicationName: "SimpleExporter",
            applicationVersion: "0.0.1",
            environment: env.ddEnvironment ?? "ci",
            clientToken: env.ddClientToken ?? "",
            endpoint: Endpoint.us,
            uploadCondition: { true },
            performancePreset: .instantDataDelivery,
            exportUnsampledSpans: false,
            exportUnsampledLogs: true
        )

        datadogExporter = try! DatadogExporter(config: exporterConfiguration)
        if launchSpanContext != nil {
            spanProcessor = SimpleSpanProcessor(spanExporter: datadogExporter).reportingOnlySampled(sampled: false)
        } else {
            spanProcessor = SimpleSpanProcessor(spanExporter: datadogExporter)
        }

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

        /// launchSpanContext will only be available when running in the app launched from UITest, so assign this as the parent
        /// when there is no one
        if let launchContext = launchSpanContext, tracerSdk.currentSpan == nil {
            spanBuilder.setParent(launchContext)
        }

        let span = spanBuilder.startSpan() as! RecordEventsReadableSpan
        _ = tracerSdk.withSpan(span)
        return span
    }

    /// This method is called form the crash reporter if the previous run crashed while running a test. Then it recreates the span with the previous information
    /// and adds the error status and information
    @discardableResult func createSpanFromCrash(spanData: SimpleSpanData, crashDate: Date?, errorType: String, errorMessage: String, errorStack: String) -> RecordEventsReadableSpan {
        var spanId: SpanId
        var parent: SpanId?
        if isBinaryUnderUITesting {
            /// We create an independent span with the test as parent
            spanId = SpanId.random()
            parent = SpanId(id: spanData.spanId)
        } else {
            /// We recreate the test span that crashed
            spanId = SpanId(id: spanData.spanId)
            parent = nil
        }

        let spanName = spanData.name
        let traceId = TraceId(idHi: spanData.traceIdHi, idLo: spanData.traceIdLo)
        let startTime = spanData.startEpochNanos
        let spanContext = SpanContext.create(traceId: traceId,
                                             spanId: spanId,
                                             traceFlags: TraceFlags().settingIsSampled(true),
                                             traceState: TraceState())
        var attributes = AttributesWithCapacity(capacity: tracerSdk.sharedState.activeTraceConfig.maxNumberOfAttributes)
        spanData.stringAttributes.forEach {
            attributes.updateValue(value: AttributeValue.string($0.value), forKey: $0.key)
        }

        attributes.updateValue(value: AttributeValue.string(DDTestTags.statusFail), forKey: DDTestTags.testStatus)
        attributes.updateValue(value: AttributeValue.string(errorType), forKey: DDTags.errorType)
        attributes.updateValue(value: AttributeValue.string(errorMessage), forKey: DDTags.errorMessage)
        attributes.updateValue(value: AttributeValue.string(errorStack), forKey: DDTags.errorStack)

        let span = RecordEventsReadableSpan.startSpan(context: spanContext,
                                                      name: spanName,
                                                      instrumentationLibraryInfo: tracerSdk.instrumentationLibraryInfo,
                                                      kind: .internal,
                                                      parentSpanId: parent,
                                                      hasRemoteParent: false,
                                                      traceConfig: tracerSdk.sharedState.activeTraceConfig,
                                                      spanProcessor: tracerSdk.sharedState.activeSpanProcessor,
                                                      clock: MonotonicClock(clock: tracerSdk.sharedState.clock),
                                                      resource: Resource(),
                                                      attributes: attributes,
                                                      links: [Link](),
                                                      totalRecordedLinks: 0,
                                                      startEpochNanos: startTime)

        var crashTimeStamp = spanData.startEpochNanos + 100
        if let timeInterval = crashDate?.timeIntervalSince1970 {
            crashTimeStamp = max(crashTimeStamp, UInt64(timeInterval * 1_000_000_000))
        }
        span.status = .internalError
        span.end(endOptions: EndSpanOptions(timestamp: crashTimeStamp))
        self.flush()
        return span
    }

    @discardableResult func createSpanFromContext(spanContext: SpanContext) -> RecordEventsReadableSpan {
        let attributes = AttributesWithCapacity(capacity: tracerSdk.sharedState.activeTraceConfig.maxNumberOfAttributes)
        let span = RecordEventsReadableSpan.startSpan(context: spanContext,
                                                      name: "ApplicationSpan",
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
                                                      startEpochNanos: 0)

        return span
    }

    func logString(string: String, date: Date? = nil) {
        if let launchContext = launchSpanContext, activeSpan == nil  {
            //This is a special case when an app executed trough a UITest, logs without a span
            return logStringAppUITested(context: launchContext, string: string, date: date)
        }

        activeSpan?.addEvent(name: "logString", attributes: ["message": AttributeValue.string(string)], timestamp: date ?? Date())
    }

    /// This method is only currently used for loggign the steps when runnning UITest
    func logString(string: String, timeIntervalSinceSpanStart: Double) {
        guard let activeSpan = activeSpan else {
            return
        }
        let eventNanos = activeSpan.startEpochNanos + UInt64(timeIntervalSinceSpanStart * 1_000_000_000)
        let timedEvent = TimedEvent(name: "logString",
                                    epochNanos: eventNanos,
                                    attributes: ["message": AttributeValue.string(string)])
        activeSpan.addEvent(event: timedEvent)
    }

    /// This method is only currently used when logging with an app being launched from a UITest, and no span has been created in the App.
    /// It creates a "non-sampled" instantaneous span that wont be serialized but where we can add the log using the SpanId and TraceId of the
    /// test Span that lunched the app.
    func logStringAppUITested(context: SpanContext, string: String, date: Date? = nil) {
        let auxSpan = createSpanFromContext(spanContext: context)
        auxSpan.addEvent(name: "logString", attributes: ["message": AttributeValue.string(string)], timestamp: date ?? Date())
        DispatchQueue.global().async {
            auxSpan.end()
            self.flush()
        }
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

        guard let currentSpan = activeSpan else {
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
