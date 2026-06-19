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
    /// Common telemetry manager. Created alongside the tracer so the API /
    /// exporter layers and every feature can record SDK self-metrics. `nil`
    /// when instrumentation telemetry is disabled or storage is unavailable.
    let telemetry: Telemetry?

    /// Logger used to emit `print()`/stderr captures and test-error context as
    /// first-class OTel `LogRecord`s through the registered LoggerProvider.
    /// `includeTraceContext` stays on (default) so the active test span's
    /// context is auto-attached as `dd.trace_id` / `dd.span_id`.
    private let loggerSdk: LoggerSdk
    private let logProcessor: LogRecordProcessor

    private var launchSpanContext: SpanContext?
    private let attributeCountLimit: UInt = 1024

    static var activeSpan: Span? { OpenTelemetry.instance.contextProvider.activeSpan ?? DDTest.current?.span }

    /// Set to `true` to enable backend debug processing for all telemetry envelopes.
    static let debugTelemetry = false

    var propagationContext: SpanContext? {
        return DDTracer.activeSpan?.context ?? launchSpanContext
    }

    var isBinaryUnderUITesting: Bool {
        return launchSpanContext != nil
    }
    
    init(id: String, version: String, exporter: ExporterProtocol?,
         api: TestOptimizationApi, enabled: Bool, launchContext: SpanContext?,
         resource: Resource = Resource(),
         logRecordExporter: LogRecordExporter? = nil,
         telemetry: Telemetry? = nil)
    {
        self.launchSpanContext = launchContext
        self.telemetry = telemetry
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
        tracerProviderSdk = TracerProviderBuilder().with(sampler: Samplers.alwaysOn)
            .with(spanLimits: SpanLimits().settingAttributeCountLimit(attributeCountLimit))
            .with(clock: DDTestMonitor.clock)
            .with(resource: resource)
            .add(spanProcessor: spanProcessor)
            .build()
        
        logProcessor = SimpleLogRecordProcessor(logRecordExporter: logRecordExporterToUse)

        let loggerProviderSdk = LoggerProviderBuilder()
            .with(clock: DDTestMonitor.clock)
            .with(resource: resource)
            .with(processors: [logProcessor])
            .build()

        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProviderSdk)
        OpenTelemetry.registerLoggerProvider(loggerProvider: loggerProviderSdk)
        
        tracerSdk = tracerProviderSdk.get(instrumentationName: id, instrumentationVersion: version) as! TracerSdk
        loggerSdk = loggerProviderSdk
            .loggerBuilder(instrumentationScopeName: id)
            .setInstrumentationVersion(version)
            .build() as! LoggerSdk
    }

    deinit {
        // Deregister our SDK from the global OpenTelemetry singleton, restoring
        // the default (no-op) providers. Otherwise the shut-down SDK provider
        // stays registered and span creation returns `PropagatedSpan`, which
        // crashes the `as! SpanSdk` casts. A new `DDTracer` re-registers a live
        // SDK provider.
        OpenTelemetry.registerTracerProvider(tracerProvider: DefaultTracerProvider.instance)
        OpenTelemetry.registerLoggerProvider(loggerProvider: DefaultLoggerProvider.instance)
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

        // `Bundle.main` is only the product under test when an app hosts the
        // tests; for host-less test bundles it is the bare `xctest` runner. Let
        // the resolver pick the right bundle (app / product framework / xctest)
        // and honor a `DD_VERSION` override.
        let (appName, appVersion) = Bundle.productUnderTest(
            schemeName: DDTestMonitor.envReader["XCODE_SCHEME_NAME"],
            versionOverride: conf.applicationVersion
        )
        
        let sdkName = Bundle.sdk.name
        let sdkVersion = Bundle.sdk.version ?? "<unknown>"

        let payloadCompression: Bool
        // When reporting tests to local server
        switch conf.endpoint {
        case let .other(testsBaseURL: tURL, logsBaseURL: _):
            payloadCompression = false
            Log.print("Reporting tests to \(tURL.absoluteURL)")
        default: payloadCompression = true
        }
        
        let hostnameToReport = Log.measure(name: "resolveHostname") {
            DDTestMonitor.developerMachineHostName.flatMap { name in
                conf.reportHostname && !name.isEmpty ? name : nil
            }
        }

        let metadata = SpanMetadata(libraryVersion: DDTestMonitor.tracerVersion,
                                    env: DDTestMonitor.env,
                                    capabilities: .libraryCapabilities)

        // Sync the clock before creating the API service so its date provider
        // is ready. SyncingClock absorbs NTP failures internally — no replacement needed.
        Log.measure(name: "NTP clock sync") {
            waitForAsync { await DDTestMonitor.clock.sync() }
        }

        let exporterConfiguration = ExporterConfiguration(
            environment: env.environment,
            metadata: metadata,
            logger: Log.instance
        )

        let api = Log.measure(name: "TestOptimizationApiService init") {
            TestOptimizationApiService(
                serviceName: env.service,
                environment: env.environment,
                applicationName: appName,
                applicationVersion: appVersion,
                libraryVersion: sdkVersion,
                device: env.platform.device,
                hostname: hostnameToReport,
                kernelInfo: env.platform.kernelInfo,
                languageVersion: env.platform.languageVersion,
                runtimeName: env.platform.runtimeName,
                runtimeVersion: env.platform.runtimeVersion,
                apiKey: conf.apiKey ?? "",
                endpoint: conf.endpoint.exporterEndpoint,
                clientId: String(SpanId.random().rawValue),
                payloadCompression: payloadCompression,
                logger: Log.instance,
                dateProvider: DDTestMonitor.clock,
                debugNetworkRequests: conf.extraDebugNetwork,
                debugTelemetry: DDTracer.debugTelemetry
            )
        }
        var resource = Resource()
        resource.applicationName = appName
        resource.applicationVersion = appVersion
        resource.environment = env.environment
        resource.service = env.service
        resource.sdkLanguage = "swift"
        resource.sdkName = sdkName
        resource.sdkVersion = sdkVersion

        // Build the telemetry manager before the exporter so its observers can
        // be wired into the exporter's upload/serialization pipeline.
        let telemetry: Telemetry? = conf.instrumentationTelemetryEnabled
            ? DDTracer.makeTelemetry(api: api, configuration: exporterConfiguration,
                                     flushInterval: conf.telemetryFlushInterval,
                                     heartbeatInterval: conf.telemetryHeartbeatInterval,
                                     distributionCap: conf.telemetryDistributionBufferSize)
            : nil

        // Exporter files live under the cache manager's session directory so
        // they stay scoped to this test run and get cleaned up alongside the
        // rest of the per-session state.
        let eventsExporter: Exporter?
        if let storage = try? DDTestMonitor.cacheManager?.session(feature: "exporter") {
            eventsExporter = Log.measure(name: "Exporter init") {
                try? Exporter(config: exporterConfiguration, api: api, storage: storage,
                              observers: DDTracer.exporterObservers(telemetry: telemetry))
            }
        } else {
            Log.print("Exporter init skipped: cache manager unavailable")
            eventsExporter = nil
        }

        self.init(id: appName, version: appVersion,
                  exporter: eventsExporter, api: api,
                  enabled: !conf.disableTracesExporting,
                  launchContext: launchSpanContext,
                  resource: resource,
                  logRecordExporter: logRecordExporter,
                  telemetry: telemetry)
    }

    /// Build the common telemetry manager wired to the SDK's telemetry intake,
    /// reusing the exporter's configuration. Returns `nil` when the backing
    /// storage or exporter can't be created, in which case telemetry is simply
    /// not gathered.
    private static func makeTelemetry(api: TestOptimizationApi, configuration: ExporterConfiguration,
                                      flushInterval: TimeInterval, heartbeatInterval: TimeInterval,
                                      distributionCap: Int) -> Telemetry?
    {
        guard let cacheManager = DDTestMonitor.cacheManager,
              let storage = try? cacheManager.session(feature: "telemetry")
        else {
            Log.print("Telemetry init skipped: cache manager unavailable")
            return nil
        }

        guard let telemetryExporter = try? TelemetryExporter(config: configuration,
                                                             storage: storage,
                                                             api: api.telemetry)
        else {
            Log.print("Telemetry init skipped: telemetry exporter unavailable")
            return nil
        }

        return Telemetry(api: api.telemetry,
                         exporter: telemetryExporter,
                         flushInterval: flushInterval,
                         heartbeatInterval: heartbeatInterval,
                         distributionCap: distributionCap,
                         clock: DDTestMonitor.clock,
                         configuration: Self.telemetryConfiguration())
    }

    /// Snapshot the current SDK configuration as `TelemetryConfigItem` values for
    /// the `app-started` payload. Origin is `.envVar` when the user set the key
    /// explicitly, `.default` otherwise.
    private static func telemetryConfiguration() -> [TelemetryConfigItem] {
        let conf = DDTestMonitor.config
        let env  = DDTestMonitor.envReader

        func item(_ key: EnvironmentKey, _ value: JSONGeneric) -> TelemetryConfigItem {
            TelemetryConfigItem(name: key.rawValue, value: value,
                                origin: env.has(key) ? .envVar : .default)
        }

        return [
            item(.enableCiVisibilityGitUpload,     .bool(conf.gitUploadEnabled)),
            item(.enableCiVisibilityGitUnshallow,  .bool(conf.gitUnshallowEnabled)),
            item(.enableCiVisibilityCodeCoverage,  .bool(conf.codeCoverageEnabled)),
            item(.enableCiVisibilityITR,            .bool(conf.tiaEnabled)),
            item(.enableCiVisibilityEFD,            .bool(conf.efdEnabled)),
            item(.enableCiVisibilityFlakyRetries,  .bool(conf.testRetriesEnabled)),
            item(.testManagementEnabled,            .bool(conf.testManagementEnabled)),
            item(.instrumentationTelemetryEnabled, .bool(conf.instrumentationTelemetryEnabled)),
        ]
    }

    /// Build the exporter's telemetry observers, mapping each upload feature to
    /// its `endpoint_payload.*` metrics tagged by endpoint (spans → `test_cycle`,
    /// coverage → `code_coverage`). Empty when telemetry is disabled.
    private static func exporterObservers(telemetry: Telemetry?) -> ExporterObservers {
        guard let telemetry else { return .init() }
        return ExporterObservers(
            spans: endpointPayloadObservers(telemetry: telemetry, endpoint: .testCycle),
            coverage: endpointPayloadObservers(telemetry: telemetry, endpoint: .codeCoverage)
        )
    }

    private static func endpointPayloadObservers(telemetry: Telemetry,
                                                 endpoint: Telemetry.Endpoint) -> ExporterObservers.Feature
    {
        let onEnqueued: (@Sendable () -> Void)?
        if endpoint == .testCycle {
            onEnqueued = { telemetry.metrics.events.enqueuedForSerialization.add(1) }
        } else {
            onEnqueued = nil
        }
        return ExporterObservers.Feature(
            // Transport facts (size sent, duration, status) come from the upload
            // request itself.
            request: Telemetry.RequestMetricsObserver(
                onRequest: { telemetry.metrics.endpointPayload.requests.add(endpoint: endpoint) },
                onDurationMs: { telemetry.metrics.endpointPayload.requestsMs.record($0, endpoint: endpoint) },
                onRequestBytes: { telemetry.metrics.endpointPayload.bytes.record(Double($0), endpoint: endpoint) },
                onError: { telemetry.metrics.endpointPayload.requestsErrors.add(errorType: $0, endpoint: endpoint) }
            ),
            // The worker owns the batch lifecycle; only `dropped` is unique to it.
            upload: Telemetry.UploadMetricsObserver(
                onDropped: { _ in telemetry.metrics.endpointPayload.dropped.add(endpoint: endpoint) }
            ),
            // Serialization happens at the storage layer.
            payload: Telemetry.PayloadMetricsObserver(
                onEnqueued: onEnqueued,
                onFinalized: { count, serializationMs in
                    telemetry.metrics.endpointPayload.eventsCount.record(Double(count), endpoint: endpoint)
                    telemetry.metrics.endpointPayload.eventsSerializationMs.record(serializationMs, endpoint: endpoint)
                }
            )
        )
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

    /// Asks the RUM process (instrumented app under UI test) to flush its data.
    /// Cross-process, so it isn't covered by the local provider shutdown and is
    /// requested on both flush and shutdown.
    private func flushRUM() {
        guard let rumPort = DDTestMonitor.instance?.rumPort else { return }
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

    func flush() {
        flushRUM()
        self.tracerProviderSdk.forceFlush()
        _ = self.logProcessor.forceFlush()
        self.telemetry?.flush()
        Log.debug("Tracer flush finished")
    }

    func shutdown() {
        // No `flush()` here: shutting the providers down below flushes spans and
        // logs properly — and the spans pipeline does it race-free via the
        // sealed `FileWriter.stop()`. A pre-shutdown flush would be redundant
        // and could skip a span still being written. We only forward the
        // cross-process RUM flush, which provider shutdown doesn't cover.
        flushRUM()
        self.tracerProviderSdk.shutdown()
        _ = self.logProcessor.shutdown()
        self.telemetry?.shutdown()
        Log.debug("Tracer shutdown")
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
        for tag in tags {
            self[string: .allTest, tag.key] = tag.value
        }
        for tag in git {
            self[string: .allTest, tag.key] = tag.value
        }
        for tag in ci {
            self[string: .allTest, tag.key] = tag.value
        }
        self[string: .allTest, DDTestSessionTags.testSessionName] = sessionName
        self[bool: .allTest, DDTags.isUserProvidedService] = isUserProvidedService
        
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
    static var allTest: Self { "test_levels" }
}
