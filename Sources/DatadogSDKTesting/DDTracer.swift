/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@_implementationOnly import DatadogExporter
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
    var datadogExporter: DatadogExporter?
    private var launchSpanContext: SpanContext?
    let backgroundWorkQueue = DispatchQueue(label: "com.otel.datadog.logswriter")

    static var activeSpan: Span? {
        return OpenTelemetrySDK.instance.contextProvider.activeSpan ??
        DDTestMonitor.instance?.currentTest?.span
    }

    var propagationContext: SpanContext? {
        return DDTracer.activeSpan?.context ?? launchSpanContext
    }

    var isBinaryUnderUITesting: Bool {
        return launchSpanContext != nil
    }

    init() {
        let env = DDTestMonitor.env
        if let envTraceId = env.launchEnvironmentTraceId,
           let envSpanId = env.launchEnvironmentSpanId
        {
            let launchTraceId = TraceId(fromHexString: envTraceId)
            let launchSpanId = SpanId(fromHexString: envSpanId)
            launchSpanContext = SpanContext.create(traceId: launchTraceId,
                                                   spanId: launchSpanId,
                                                   traceFlags: TraceFlags().settingIsSampled(false),
                                                   traceState: TraceState())
        }

        let tracerProvider = OpenTelemetrySDK.instance.tracerProvider
        tracerProvider.updateActiveSampler(Samplers.alwaysOn)
        let spanLimits = tracerProvider.getActiveSpanLimits().settingAttributeCountLimit(1024)
        tracerProvider.updateActiveSpanLimits(spanLimits)

        let bundle = Bundle.main
        let identifier = bundle.bundleIdentifier ?? "com.datadoghq.DatadogSDKTesting"
        let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

        tracerSdk = tracerProvider.get(instrumentationName: identifier, instrumentationVersion: version) as! TracerSdk

        var endpoint: Endpoint
        switch env.tracesEndpoint {
            case "us", "US", "us1", "US1", "https://app.datadoghq.com", "app.datadoghq.com", "datadoghq.com":
                endpoint = Endpoint.us1
            case "us3", "US3", "https://us3.datadoghq.com", "us3.datadoghq.com":
                endpoint = Endpoint.us3
            case "eu", "EU", "eu1", "EU1","https://app.datadoghq.eu", "app.datadoghq.eu", "datadoghq.eu":
                endpoint = Endpoint.eu1
            case "gov", "GOV", "us1_fed", "US1_FED","https://app.ddog-gov.com", "app.ddog-gov.com", "ddog-gov.com":
                endpoint = Endpoint.us1_fed
            default:
                endpoint = Endpoint.us1
        }

        // When reporting tests to local server
        if let localPort = env.localTestEnvironmentPort {
            let localURL = URL(string: "http://localhost:\(localPort)/")!
            endpoint = Endpoint.custom(tracesURL: localURL, logsURL: localURL, metricsURL: localURL)
            print("[DDSwiftTesting] Reporting tests to \(localURL.absoluteURL)")
        }

        let exporterConfiguration = ExporterConfiguration(
            serviceName: env.ddService ?? env.getRepositoryName() ?? "unknown-swift-repo",
            resource: "Resource",
            applicationName: identifier,
            applicationVersion: version,
            environment: env.ddEnvironment ?? (env.isCi ? "ci" : "none"),
            apiKey: env.ddApikeyOrClientToken ?? "",
            endpoint: endpoint,
            uploadCondition: { true },
            performancePreset: .instantDataDelivery,
            exportUnsampledSpans: false,
            exportUnsampledLogs: true
        )
        datadogExporter = try? DatadogExporter(config: exporterConfiguration)

        guard let exporterToUse: SpanExporter = env.disableTracesExporting ? InMemoryExporter() : datadogExporter else {
            print("[DDSwiftTesting] Failed creating Datadog exporter.")
            return
        }

        var spanProcessor: SpanProcessor
        if launchSpanContext != nil {
            spanProcessor = SimpleSpanProcessor(spanExporter: exporterToUse).reportingOnlySampled(sampled: false)
        } else {
            spanProcessor = SimpleSpanProcessor(spanExporter: exporterToUse)
        }

        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(spanProcessor)
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(OriginSpanProcessor())
    }

    func startSpan(name: String, attributes: [String: String], date: Date? = nil) -> Span {
        let spanBuilder = tracerSdk.spanBuilder(spanName: name)
        attributes.forEach {
            spanBuilder.setAttribute(key: $0.key, value: $0.value)
        }
        spanBuilder.setStartTime(time: date ?? Date())

        /// launchSpanContext will only be available when running in the app launched from UITest, so assign this as the parent
        /// when there is no one
        if let launchContext = launchSpanContext {
            spanBuilder.setParent(launchContext)
        } else {
            spanBuilder.setNoParent()
        }

        let span = spanBuilder.startSpan()
        OpenTelemetrySDK.instance.contextProvider.setActiveSpan(span)
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

        let tracerProvider = OpenTelemetrySDK.instance.tracerProvider
        var attributes = AttributesDictionary(capacity: OpenTelemetrySDK.instance.tracerProvider.getActiveSpanLimits().attributeCountLimit)
        spanData.stringAttributes.forEach {
            attributes.updateValue(value: AttributeValue.string($0.value), forKey: $0.key)
        }

        attributes.updateValue(value: AttributeValue.string(DDTagValues.statusFail), forKey: DDTestTags.testStatus)
        attributes.updateValue(value: AttributeValue.string(errorType), forKey: DDTags.errorType)
        if errorStack.count < 5000 {
            attributes.updateValue(value: AttributeValue.string(errorMessage), forKey: DDTags.errorMessage)
            attributes.updateValue(value: AttributeValue.string(errorStack), forKey: DDTags.errorStack)
        } else {
            attributes.updateValue(value: AttributeValue.string(errorMessage + ". Check error.stack for the full crash log."), forKey: DDTags.errorMessage)
            let splitted = errorStack.split(by: 5000)
            for i in 0 ..< splitted.count {
                attributes.updateValue(value: AttributeValue.string(splitted[i]), forKey: "\(DDTags.errorStack).\(String(format: "%d", i))")
            }
        }

        let spanProcessor = MultiSpanProcessor(spanProcessors: tracerProvider.getActiveSpanProcessors())
        let span = RecordEventsReadableSpan.startSpan(context: spanContext,
                                                      name: spanName,
                                                      instrumentationLibraryInfo: tracerSdk.instrumentationLibraryInfo,
                                                      kind: .internal,
                                                      parentContext: parentContext,
                                                      hasRemoteParent: false,
                                                      spanLimits: tracerProvider.getActiveSpanLimits(),
                                                      spanProcessor: spanProcessor,
                                                      clock: tracerProvider.getActiveClock(),
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
        let tracerProvider = OpenTelemetrySDK.instance.tracerProvider
        let attributes = AttributesDictionary(capacity: tracerProvider.getActiveSpanLimits().attributeCountLimit)
        let spanProcessor = MultiSpanProcessor(spanProcessors: tracerProvider.getActiveSpanProcessors())

        let span = RecordEventsReadableSpan.startSpan(context: launchSpanContext!,
                                                      name: "ApplicationSpan",
                                                      instrumentationLibraryInfo: tracerSdk.instrumentationLibraryInfo,
                                                      kind: .internal,
                                                      parentContext: nil,
                                                      hasRemoteParent: false,
                                                      spanLimits: tracerProvider.getActiveSpanLimits(),
                                                      spanProcessor: spanProcessor,
                                                      clock: tracerProvider.getActiveClock(),
                                                      resource: Resource(),
                                                      attributes: attributes,
                                                      links: [SpanData.Link](),
                                                      totalRecordedLinks: 0,
                                                      startTime: Date())

        return span
    }

    private func attributesForString(_ string: String) -> [String: AttributeValue] {
        return ["message": AttributeValue.string(string),
                DDGenericTags.origin: AttributeValue.string(DDTagValues.originCiApp)]
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
        backgroundWorkQueue.async {
            auxSpan.status = .ok
            auxSpan.end()
            OpenTelemetrySDK.instance.tracerProvider.forceFlush()
        }
    }

    func flush() {
        backgroundWorkQueue.sync {
            OpenTelemetrySDK.instance.tracerProvider.forceFlush()
        }
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
                DDHeaders.ddSampled.rawValue: "1"
        ]
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

        tracerSdk.textFormat.inject(spanContext: propagationContext, carrier: &headers, setter: HeaderSetter())
        headers.merge(datadogHeaders(forContext: propagationContext)) { current, _ in current }
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
        headers.merge(datadogHeaders(forContext: propagationContext)) { current, _ in current }
        return headers
    }

    func endpointURLs() -> Set<String> {
        return datadogExporter?.endpointURLs() ?? Set<String>()
    }
}
