/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@_implementationOnly import EventsExporter
import Foundation
@_implementationOnly import InMemoryExporter
@_implementationOnly import OpenTelemetryApi
@_implementationOnly import OpenTelemetrySdk

enum DDHeaders: String, CaseIterable {
    case traceIDField = "x-datadog-trace-id"
    case parentSpanIDField = "x-datadog-parent-id"
    case originField = "x-datadog-origin"
    case ddSamplingPriority = "x-datadog-sampling-priority"
    case ddSampled = "x-datadog-sampled"
}

internal class DDTracer {
    let tracerSdk: TracerSdk
    let tracerProviderSdk: TracerProviderSdk
    var eventsExporter: EventsExporter?
    private var launchSpanContext: SpanContext?

    private let attributeCountLimit: UInt = 1024

    static var activeSpan: Span? {
        return OpenTelemetry.instance.contextProvider.activeSpan ??
            DDTestMonitor.instance?.currentTest?.span
    }

    var propagationContext: SpanContext? {
        return DDTracer.activeSpan?.context ?? launchSpanContext
    }

    var isBinaryUnderUITesting: Bool {
        return launchSpanContext != nil
    }

    init() {
        let conf = DDTestMonitor.config
        let env = DDTestMonitor.env
        if let envTraceId = conf.tracerTraceId,
           let envSpanId = conf.tracerSpanId
        {
            let launchTraceId = TraceId(fromHexString: envTraceId)
            let launchSpanId = SpanId(fromHexString: envSpanId)
            launchSpanContext = SpanContext.create(traceId: launchTraceId,
                                                   spanId: launchSpanId,
                                                   traceFlags: TraceFlags().settingIsSampled(false),
                                                   traceState: TraceState())
        }

        let bundle = Bundle.main
        let identifier = bundle.bundleIdentifier ?? "com.datadoghq.DatadogSDKTesting"
        let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

        let payloadCompression: Bool
        // When reporting tests to local server
        switch conf.endpoint {
        case let .custom(testsURL: tURL, logsURL: _), let .other(testsBaseURL: tURL, logsBaseURL: _):
            payloadCompression = false
            Log.print("Reporting tests to \(tURL.absoluteURL)")
        default: payloadCompression = true
        }

        let hostnameToReport: String? = (conf.reportHostname && !DDTestMonitor.developerMachineHostName.isEmpty) ? DDTestMonitor.developerMachineHostName : nil

        let exporterConfiguration = ExporterConfiguration(
            serviceName: conf.service ?? env.git.repositoryName ?? "unknown-swift-repo",
            libraryVersion: DDTestMonitor.tracerVersion,
            applicationName: identifier,
            applicationVersion: version,
            environment: env.environment,
            hostname: hostnameToReport,
            apiKey: conf.apiKey ?? "",
            endpoint: conf.endpoint.exporterEndpoint,
            payloadCompression: payloadCompression,
            performancePreset: .instantDataDelivery,
            exporterId: String(SpanId.random().rawValue),
            logger: Log.instance
        )
        eventsExporter = try? EventsExporter(config: exporterConfiguration)

        let exporterToUse: SpanExporter

        if conf.disableTracesExporting {
            exporterToUse = InMemoryExporter()
        } else if let exporter = eventsExporter {
            exporterToUse = exporter as SpanExporter
        } else {
            Log.print("Failed creating Datadog exporter.")
            exporterToUse = InMemoryExporter()
        }

        var spanProcessor: SpanProcessor
        if launchSpanContext != nil {
            spanProcessor = SimpleSpanProcessor(spanExporter: exporterToUse).reportingOnlySampled(sampled: false)
        } else {
            spanProcessor = SimpleSpanProcessor(spanExporter: exporterToUse)
        }

        // sync clock
        try! DDTestMonitor.clock.sync()
        
        tracerProviderSdk = TracerProviderBuilder().with(sampler: Samplers.alwaysOn)
            .with(spanLimits: SpanLimits().settingAttributeCountLimit(attributeCountLimit))
            .with(clock: DDTestMonitor.clock)
            .add(spanProcessor: spanProcessor)
            .build()

        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProviderSdk)
        tracerSdk = tracerProviderSdk.get(instrumentationName: identifier, instrumentationVersion: version) as! TracerSdk
    }

    func startSpan(name: String, attributes: [String: String], startTime: Date? = nil) -> Span {
        let spanBuilder = tracerSdk.spanBuilder(spanName: name)
        attributes.forEach {
            spanBuilder.setAttribute(key: $0.key, value: $0.value)
        }
        if let startTime = startTime {
            spanBuilder.setStartTime(time: startTime)
        }
        /// launchSpanContext will only be available when running in the app launched from UITest, so assign this as the parent
        /// when there is no one
        if let launchContext = launchSpanContext {
            spanBuilder.setParent(launchContext)
        } else {
            spanBuilder.setNoParent()
        }
        spanBuilder.setActive(true)
        let span = spanBuilder.startSpan()
        return span
    }

    /// This method is called form the crash reporter if the previous run crashed while running a test. Then it recreates the span with the previous information
    /// and adds the error status and information
    @discardableResult func createSpanFromCrash(spanData: SimpleSpanData, crashDate: Date?, errorType: String, errorMessage: String, errorStack: String) -> RecordEventsReadableSpan {
        var spanId: SpanId
        var parentContext: SpanContext?
        let traceId = TraceId(idHi: spanData.traceIdHi, idLo: spanData.traceIdLo)
        if isBinaryUnderUITesting {
            /// We create an independent span with the test as parent
            spanId = SpanId.random()
            parentContext = SpanContext.create(traceId: traceId,
                                               spanId: SpanId(id: spanData.spanId),
                                               traceFlags: TraceFlags().settingIsSampled(true),
                                               traceState: TraceState())
        } else {
            /// We recreate the test span that crashed
            spanId = SpanId(id: spanData.spanId)
            parentContext = nil
        }

        let spanName = spanData.name
        let startTime = spanData.startTime
        let spanContext = SpanContext.create(traceId: traceId,
                                             spanId: spanId,
                                             traceFlags: TraceFlags().settingIsSampled(true),
                                             traceState: TraceState())

        var attributes = AttributesDictionary(capacity: Int(attributeCountLimit))
        spanData.stringAttributes.forEach {
            attributes.updateValue(value: AttributeValue.string($0.value), forKey: $0.key)
        }

        attributes.updateValue(value: AttributeValue.string(DDTagValues.statusFail), forKey: DDTestTags.testStatus)
        attributes.updateValue(value: AttributeValue.string(errorType), forKey: DDTags.errorType)
        if errorStack.count < 5000 {
            attributes.updateValue(value: AttributeValue.string(errorMessage), forKey: DDTags.errorMessage)
            attributes.updateValue(value: AttributeValue.string(errorStack), forKey: DDTags.errorStack)
        } else {
            attributes.updateValue(value: AttributeValue.string(errorMessage + ". Check error.crash_log for the full crash log."), forKey: DDTags.errorMessage)

            let crashedThread = DDSymbolicator.calculateCrashedThread(stack: errorStack)
            attributes.updateValue(value: AttributeValue.string(crashedThread), forKey: "\(DDTags.errorStack)")

            let splitted = errorStack.split(by: 5000)
            for i in 0 ..< splitted.count {
                attributes.updateValue(value: AttributeValue.string(splitted[i]), forKey: "\(DDTags.errorCrashLog).\(String(format: "%02d", i))")
            }
        }

        let spanProcessor = MultiSpanProcessor(spanProcessors: tracerProviderSdk.getActiveSpanProcessors())
        let span = RecordEventsReadableSpan.startSpan(context: spanContext,
                                                      name: spanName,
                                                      instrumentationScopeInfo: tracerSdk.instrumentationScopeInfo,
                                                      kind: .internal,
                                                      parentContext: parentContext,
                                                      hasRemoteParent: false,
                                                      spanLimits: tracerProviderSdk.getActiveSpanLimits(),
                                                      spanProcessor: spanProcessor,
                                                      clock: tracerProviderSdk.getActiveClock(),
                                                      resource: Resource(),
                                                      attributes: attributes,
                                                      links: [SpanData.Link](),
                                                      totalRecordedLinks: 0,
                                                      startTime: startTime)

        var minimumCrashTime = spanData.startTime.addingTimeInterval(TimeInterval.fromMicroseconds(1))
        if let crashDate = crashDate {
            minimumCrashTime = max(minimumCrashTime, crashDate)
        }
        span.status = .error(description: errorMessage)
        span.end(time: minimumCrashTime)
        self.flush()
        return span
    }

    @discardableResult func createSpanFromLaunchContext() -> RecordEventsReadableSpan {
        let attributes = AttributesDictionary(capacity: tracerProviderSdk.getActiveSpanLimits().attributeCountLimit)
        let spanProcessor = MultiSpanProcessor(spanProcessors: tracerProviderSdk.getActiveSpanProcessors())

        let span = RecordEventsReadableSpan.startSpan(context: launchSpanContext!,
                                                      name: "ApplicationUnderTest",
                                                      instrumentationScopeInfo: tracerSdk.instrumentationScopeInfo,
                                                      kind: .internal,
                                                      parentContext: nil,
                                                      hasRemoteParent: false,
                                                      spanLimits: tracerProviderSdk.getActiveSpanLimits(),
                                                      spanProcessor: spanProcessor,
                                                      clock: tracerProviderSdk.getActiveClock(),
                                                      resource: Resource(),
                                                      attributes: attributes,
                                                      links: [SpanData.Link](),
                                                      totalRecordedLinks: 0,
                                                      startTime: Date())

        return span
    }

    private func testAttributes() -> [String: AttributeValue] {
        guard let currentTest = DDTestMonitor.instance?.currentTest else {
            return [:]
        }
        return [DDTestTags.testName: AttributeValue.string(currentTest.name),
                DDTestTags.testSuite: AttributeValue.string(currentTest.suite.name),
                DDTestTags.testModule: AttributeValue.string(currentTest.module.bundleName)]
    }

    private func attributesForString(_ string: String) -> [String: AttributeValue] {
        return testAttributes().merging(["message": AttributeValue.string(string)]) { _, other in other }
    }

    private func attributesForError(_ string: String) -> [String: AttributeValue] {
        return testAttributes().merging(["message": AttributeValue.string(string),
                                         "status": AttributeValue.string("error")]) { _, other in other }
    }

    func logString(string: String, date: Date? = nil) {
        if launchSpanContext != nil, DDTracer.activeSpan == nil {
            // This is a special case when an app executed trough a UITest, logs without a span
            return logStringAppUITested(string: string, date: date)
        }

        DDTracer.activeSpan?.addEvent(name: "logString", attributes: attributesForString(string), timestamp: date ?? Date())
    }

    /// This method is only currently used for loggign the steps when runnning UITest
    func logString(string: String, timeIntervalSinceSpanStart: Double) {
        guard let activeSpan = DDTracer.activeSpan as? RecordEventsReadableSpan else {
            return
        }
        let timestamp = activeSpan.startTime.addingTimeInterval(timeIntervalSinceSpanStart)
        activeSpan.addEvent(name: "logString", attributes: attributesForString(string), timestamp: timestamp)
    }

    /// This method is only currently used when logging with an app being launched from a UITest, and no span has been created in the App.
    /// It creates a "non-sampled" instantaneous span that wont be serialized but where we can add the log using the SpanId and TraceId of the
    /// test Span that lunched the app.
    func logStringAppUITested(string: String, date: Date? = nil) {
        let auxSpan = createSpanFromLaunchContext()
        auxSpan.addEvent(name: "logString", attributes: attributesForString(string), timestamp: date ?? Date())
        auxSpan.status = .ok
        auxSpan.end()
    }

    /// This method is only currently used when logging with an app being launched from a UITest, and no span has been created in the App.
    func logError(string: String, date: Date? = nil) {
        guard DDTestMonitor.config.enableStderrInstrumentation || DDTestMonitor.config.enableStdoutInstrumentation else {
            return
        }
        DDTracer.activeSpan?.addEvent(name: "logString", attributes: attributesForError(string), timestamp: date ?? Date())
    }

    func flush() {
        if let rumPort = DDTestMonitor.instance?.rumPort {
            let timeout: CFTimeInterval = 10.0
            let status = CFMessagePortSendRequest(
                rumPort,
                DDCFMessageID.forceFlush, // Message ID for asking RUM to flush all data
                nil,
                timeout,
                timeout,
                "kCFRunLoopDefaultMode" as CFString,
                nil
            )
            if status == kCFMessagePortSuccess {
                Log.debug("DDCFMessageID.forceFlush finished")
            } else {
                Log.debug("CFMessagePortCreateRemote request to DatadogRUMTestingPort failed")
            }
        }
        
        self.tracerProviderSdk.forceFlush()
        Log.debug("Tracer flush finished")
    }

    func addPropagationsHeadersToEnvironment() {
        let headers = tracePropagationHTTPHeaders()
        headers.forEach {
            setenv($0.key, $0.value, 1)
        }
    }

    func datadogHeaders(forContext context: SpanContext?) -> [String: String] {
        guard let context = context else {
            return [String: String]()
        }
        return [DDHeaders.traceIDField.rawValue: String(context.traceId.rawLowerLong),
                DDHeaders.parentSpanIDField.rawValue: String(context.spanId.rawValue),
                DDHeaders.originField.rawValue: DDTagValues.originCiApp,
                DDHeaders.ddSamplingPriority.rawValue: "1",
                DDHeaders.ddSampled.rawValue: "1"]
    }

    func tracePropagationHTTPHeaders() -> [String: String] {
        var headers = [String: String]()

        struct HeaderSetter: Setter {
            func set(carrier: inout [String: String], key: String, value: String) {
                carrier[key] = value
            }
        }

        guard let propagationContext = propagationContext else {
            return headers
        }

        OpenTelemetry.instance.propagators.textMapPropagator.inject(spanContext: propagationContext, carrier: &headers, setter: HeaderSetter())
        if !DDTestMonitor.config.disableRUMIntegration {
            headers.merge(datadogHeaders(forContext: propagationContext)) { current, _ in current }
        }
        return headers
    }

    func environmentPropagationHTTPHeaders() -> [String: String] {
        var headers = [String: String]()

        struct HeaderSetter: Setter {
            func set(carrier: inout [String: String], key: String, value: String) {
                carrier[key] = value
            }
        }

        guard let propagationContext = propagationContext else {
            return headers
        }

        EnvironmentContextPropagator().inject(spanContext: propagationContext, carrier: &headers, setter: HeaderSetter())
        if !DDTestMonitor.config.disableRUMIntegration {
            headers.merge(datadogHeaders(forContext: propagationContext)) { current, _ in current }
            headers[EnvironmentKey.testExecutionId.rawValue] = String(propagationContext.traceId.rawLowerLong)
        }
        return headers
    }

    func endpointURLs() -> Set<String> {
        return eventsExporter?.endpointURLs() ?? Set<String>()
    }
}
