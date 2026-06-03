/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

internal import EventsExporter
import Foundation
internal import OpenTelemetryApi
internal import OpenTelemetrySdk

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
    let maxObjectSize: UInt64
    /// OTel `Resource` describing this SDK (service / version / env / sdk.* tags).
    /// Reused by the telemetry meter provider so self-metrics carry the same
    /// identity as spans and logs.
    let resource: Resource
    var eventsExporter: ExporterProtocol?
    /// Backend APIs owned by the SDK (not by the exporter). Held here so
    /// feature factories don't need to reach through `eventsExporter` to talk
    /// to the backend.
    var api: TestOptimizationApi

    /// Logger used to emit `print()`/stderr captures and test-error context as
    /// first-class OTel `LogRecord`s through the registered LoggerProvider.
    /// `includeTraceContext` stays on (default) so the active test span's
    /// context is auto-attached as `dd.trace_id` / `dd.span_id`.
    private let loggerSdk: LoggerSdk

    private var launchSpanContext: SpanContext?
    private let attributeCountLimit: UInt = 1024

    static var activeSpan: Span? { OpenTelemetry.instance.contextProvider.activeSpan ?? DDTest.current?.span }

    var propagationContext: SpanContext? {
        return DDTracer.activeSpan?.context ?? launchSpanContext
    }

    var isBinaryUnderUITesting: Bool {
        return launchSpanContext != nil
    }
    
    init(id: String, version: String, exporter: ExporterProtocol?,
         api: TestOptimizationApi, enabled: Bool, launchContext: SpanContext?,
         resource: Resource = Resource(),
         logRecordExporter: LogRecordExporter? = nil)
    {
        self.launchSpanContext = launchContext
        self.eventsExporter = exporter
        self.api = api
        self.resource = resource
        self.maxObjectSize = exporter?.maxObjectSize ?? 262144

        let spanExporterToUse: SpanExporter
        let defaultLogRecordExporter: LogRecordExporter
        if !enabled {
            spanExporterToUse = NoopSpanExporter()
            defaultLogRecordExporter = NoopLogRecordExporter.instance
        } else if let exporter = eventsExporter {
            spanExporterToUse = exporter as SpanExporter
            defaultLogRecordExporter = exporter as LogRecordExporter
        } else {
            Log.print("Failed creating Datadog exporter.")
            spanExporterToUse = NoopSpanExporter()
            defaultLogRecordExporter = NoopLogRecordExporter.instance
        }
        // The `logRecordExporter` override exists so tests can intercept
        // emissions with an in-memory exporter without touching the rest of
        // the pipeline. Production callers never pass it.
        let logRecordExporterToUse: LogRecordExporter = logRecordExporter ?? defaultLogRecordExporter

        let spanProcessor: SpanProcessor
        if launchSpanContext != nil {
            spanProcessor = SimpleSpanProcessor(spanExporter: spanExporterToUse).reportingOnlySampled(sampled: false)
        } else {
            spanProcessor = SimpleSpanProcessor(spanExporter: spanExporterToUse)
        }

        // sync clock
        waitForAsync {
            do {
                try await DDTestMonitor.clock.sync()
            } catch {
                DDTestMonitor.clock = DateClock()
            }
        }

        tracerProviderSdk = TracerProviderBuilder().with(sampler: Samplers.alwaysOn)
            .with(spanLimits: SpanLimits().settingAttributeCountLimit(attributeCountLimit))
            .with(clock: DDTestMonitor.clock)
            .with(resource: resource)
            .add(spanProcessor: spanProcessor)
            .build()

        let loggerProviderSdk = LoggerProviderBuilder()
            .with(clock: DDTestMonitor.clock)
            .with(resource: resource)
            .with(processors: [SimpleLogRecordProcessor(logRecordExporter: logRecordExporterToUse)])
            .build()

        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProviderSdk)
        OpenTelemetry.registerLoggerProvider(loggerProvider: loggerProviderSdk)
        
        tracerSdk = tracerProviderSdk.get(instrumentationName: id, instrumentationVersion: version) as! TracerSdk
        loggerSdk = loggerProviderSdk
            .loggerBuilder(instrumentationScopeName: id)
            .setInstrumentationVersion(version)
            .build() as! LoggerSdk
    }

    convenience init(logRecordExporter: LogRecordExporter? = nil) {
        let conf = DDTestMonitor.config
        let env = DDTestMonitor.env
        var launchSpanContext: SpanContext? = nil
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
        case let .other(testsBaseURL: tURL, logsBaseURL: _):
            payloadCompression = false
            Log.print("Reporting tests to \(tURL.absoluteURL)")
        default: payloadCompression = true
        }
        
        let hostnameToReport = DDTestMonitor.developerMachineHostName.flatMap { name in
            conf.reportHostname && !name.isEmpty ? name : nil
        }
        
        let metadata = SpanMetadata(libraryVersion: DDTestMonitor.tracerVersion,
                                    env: DDTestMonitor.env,
                                    capabilities: .libraryCapabilities)

        let exporterConfiguration = ExporterConfiguration(
            environment: env.environment,
            metadata: metadata,
            performancePreset: .instantDataDelivery,
            logger: Log.instance
        )
        let api = TestOptimizationApiService(
            serviceName: env.service,
            environment: env.environment,
            applicationName: identifier,
            version: version,
            hostname: hostnameToReport,
            apiKey: conf.apiKey ?? "",
            endpoint: conf.endpoint.exporterEndpoint,
            clientId: String(SpanId.random().rawValue),
            payloadCompression: payloadCompression,
            logger: Log.instance,
            dateProvider: DDTestMonitor.clock,
            debugNetworkRequests: conf.extraDebugNetwork
        )
        // Exporter files live under the cache manager's session directory so
        // they stay scoped to this test run and get cleaned up alongside the
        // rest of the per-session state.
        let eventsExporter: Exporter?
        if let storage = try? DDTestMonitor.cacheManager?.session(feature: "exporter") {
            eventsExporter = try? Exporter(config: exporterConfiguration, api: api, storage: storage)
        } else {
            Log.print("Exporter init skipped: cache manager unavailable")
            eventsExporter = nil
        }

        var resource = Resource()
        resource.applicationName = identifier
        resource.applicationVersion = version
        resource.environment = env.environment
        resource.service = env.service
        resource.sdkLanguage = "swift"
        resource.sdkName = identifier
        resource.sdkVersion = DDTestMonitor.tracerVersion

        self.init(id: identifier, version: version, exporter: eventsExporter,
                  api: api,
                  enabled: !conf.disableTracesExporting, launchContext: launchSpanContext,
                  resource: resource,
                  logRecordExporter: logRecordExporter)
    }
    
    private func createSpanBuilder(name: String, attributes: [String: AttributeValue], startTime: Date? = nil) -> SpanBuilder {
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
        return spanBuilder
    }
    
    func withActiveSpan<T>(name: String, attributes: [String: AttributeValue], startTime: Date? = nil,
                           _ body: @Sendable (SpanSdk) throws -> T) rethrows -> T
    {
        let spanBuilder = createSpanBuilder(name: name, attributes: attributes, startTime: startTime)
        return try spanBuilder.withActiveSpan { span in
            try body(span as! SpanSdk)
        }
    }
    
    func withActiveSpan<T>(name: String, attributes: [String: AttributeValue], startTime: Date? = nil,
                           _ body: @Sendable (SpanSdk) async throws -> T) async rethrows -> T
    {
        let spanBuilder = createSpanBuilder(name: name, attributes: attributes, startTime: startTime)
        return try await spanBuilder.withActiveSpan { span in
            try await body(span as! SpanSdk)
        }
    }

    /// This method is called form the crash reporter if the previous run crashed while running a test. Then it recreates the span with the previous information
    /// and adds the error status and information
    @discardableResult func createSpanFromCrash(spanData: SimpleSpanData, crashDate: Date?, error: TestError) -> SpanSdk {
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
        let error = error.trimmed(maxSize: maxObjectSize - 5120) // 5k for other tags and everything else for crash log
        attributes.updateValue(value: AttributeValue.string(error.type), forKey: DDTags.errorType)
        if let message = error.message {
            attributes.updateValue(value: AttributeValue.string(message), forKey: DDTags.errorMessage)
        }
        if let stack = error.stack {
            attributes.updateValue(value: AttributeValue.string(stack), forKey: DDTags.errorStack)
        }
        if let crash = error.crashLog {
            for i in 0 ..< crash.count {
                attributes.updateValue(value: AttributeValue.string(crash[i]),
                                       forKey: "\(DDTags.errorCrashLog).\(String(format: "%02d", i))")
            }
        }

        let spanProcessor = MultiSpanProcessor(spanProcessors: tracerProviderSdk.getActiveSpanProcessors())
        let span = SpanSdk.startSpan(context: spanContext,
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
        span.status = .error(description: error.message ?? error.type)
        span.end(time: minimumCrashTime)
        self.flush()
        return span
    }

    /// Creates an OTel `SpanSdk` for a test session / module / suite lifecycle
    /// event. The caller controls the `spanId` so the wire payload's
    /// `test_session_id` / `test_module_id` / `test_suite_id` field matches the
    /// session's/module's/suite's logical id. The span flows through the
    /// registered `SimpleSpanProcessor` → `EventsExporter` → `SpansExporter`
    /// pipeline; the per-`type` dispatch in `SpansExporter.exportSpan`
    /// picks the right `Test{Session,Module,Suite}Envelope` encoder.
    func createLifecycleSpan(name: String, spanId: SpanId, startTime: Date,
                             attributes: [String: AttributeValue]) -> SpanSdk
    {
        let context = SpanContext.create(traceId: TraceId.random(),
                                         spanId: spanId,
                                         traceFlags: TraceFlags().settingIsSampled(true),
                                         traceState: TraceState())
        var attrs = AttributesDictionary(capacity: Int(attributeCountLimit))
        for (key, value) in attributes {
            attrs.updateValue(value: value, forKey: key)
        }
        let spanProcessor = MultiSpanProcessor(spanProcessors: tracerProviderSdk.getActiveSpanProcessors())
        return SpanSdk.startSpan(context: context,
                                 name: name,
                                 instrumentationScopeInfo: tracerSdk.instrumentationScopeInfo,
                                 kind: .internal,
                                 parentContext: nil,
                                 hasRemoteParent: false,
                                 spanLimits: tracerProviderSdk.getActiveSpanLimits(),
                                 spanProcessor: spanProcessor,
                                 clock: tracerProviderSdk.getActiveClock(),
                                 resource: tracerProviderSdk.getActiveResource(),
                                 attributes: attrs,
                                 links: [SpanData.Link](),
                                 totalRecordedLinks: 0,
                                 startTime: startTime)
    }

    @discardableResult func createSpanFromLaunchContext() -> SpanSdk {
        let attributes = AttributesDictionary(capacity: tracerProviderSdk.getActiveSpanLimits().attributeCountLimit)
        let spanProcessor = MultiSpanProcessor(spanProcessors: tracerProviderSdk.getActiveSpanProcessors())

        let span = SpanSdk.startSpan(context: launchSpanContext!,
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
        guard let currentTest = DDTest.active else {
            return [:]
        }
        return [DDTestTags.testName: AttributeValue.string(currentTest.name),
                DDTestTags.testSuite: AttributeValue.string(currentTest.suite.name),
                DDTestTags.testModule: AttributeValue.string(currentTest.module.name)]
    }

    func logString(string: String, date: Date? = nil) {
        // UI-test edge case: no active span, but a launchSpanContext from the
        // host harness — emit with that context so the log still correlates to
        // the test span that started this app.
        if launchSpanContext != nil, DDTracer.activeSpan == nil {
            emitLog(body: string, severity: .info, timestamp: date,
                    explicitSpanContext: launchSpanContext)
            return
        }
        emitLog(body: string, severity: .info, timestamp: date)
    }

    /// Used for logging UI-test step events at offsets relative to the active
    /// span's start time.
    func logString(string: String, timeIntervalSinceSpanStart: Double) {
        guard let activeSpan = DDTracer.activeSpan as? SpanSdk else { return }
        let timestamp = activeSpan.startTime.addingTimeInterval(timeIntervalSinceSpanStart)
        emitLog(body: string, severity: .info, timestamp: timestamp)
    }

    /// Test-assertion error context, called from DDTest. The umbrella stdout
    /// / stderr instrumentation gate is preserved because errors are written
    /// into the log pipeline rather than the test span's attributes — without
    /// the gate they'd surface even when logs are disabled.
    func logError(string: String, date: Date? = nil) {
        guard DDTestMonitor.config.enableStderrInstrumentation || DDTestMonitor.config.enableStdoutInstrumentation else {
            return
        }
        emitLog(body: string, severity: .error, timestamp: date)
    }

    /// Emit a `LogRecord` through the registered OTel LoggerProvider. The
    /// LoggerSdk auto-injects the active span context (`includeTraceContext`
    /// defaults to `true`), so `dd.trace_id` / `dd.span_id` on the wire come
    /// out matching the test span without an explicit set. Pass
    /// `explicitSpanContext` only when there is no active span but we still
    /// want correlation (the UI-test launch context case).
    private func emitLog(body: String, severity: Severity, timestamp: Date?,
                         explicitSpanContext: SpanContext? = nil)
    {
        var builder = loggerSdk.logRecordBuilder()
            .setBody(.string(body))
            .setSeverity(severity)
            .setAttributes(testAttributes())
        if let timestamp { builder = builder.setTimestamp(timestamp) }
        if let explicitSpanContext { builder = builder.setSpanContext(explicitSpanContext) }
        builder.emit()
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
        Set(api.endpointURLs.map { $0.absoluteString })
    }
}

extension SpanMetadata {    
    init(libraryVersion: String,
         tags: [String: String],
         git: [String: String],
         ci: [String: String],
         sessionName: String,
         isUserProvidedService: Bool,
         capabilities: SDKCapabilities)
    {
        self.init()
        self[string: DDGenericTags.language] = "swift"
        self[string: DDGenericTags.libraryVersion] = libraryVersion
        for type in SpanType.allTest {
            for tag in tags {
                self[string: type, tag.key] = tag.value
            }
            for tag in git {
                self[string: type, tag.key] = tag.value
            }
            for tag in ci {
                self[string: type, tag.key] = tag.value
            }
            self[string: type, DDTestSessionTags.testSessionName] = sessionName
            self[bool: type, DDTags.isUserProvidedService] = isUserProvidedService
        }
        for capability in capabilities {
            let (key, val) = capability.metadata
            self[string: .test, key] = val
        }
    }
}

extension SpanMetadata.SpanType {
    static var module: Self { .init(DDTagValues.typeModuleEnd) }
    static var session: Self { .init(DDTagValues.typeSessionEnd) }
    static var suite: Self { .init(DDTagValues.typeSuiteEnd) }
    static var test: Self { .init(DDTagValues.typeTest) }
    
    static var allTest: [Self] { [module, session, suite, test] }
}
