/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Public domain types

public protocol TelemetryPayload: Encodable {
    var requestType: TelemetryRequestType { get }
}

/// The set of telemetry request_types this service implements.
public enum TelemetryRequestType: String, Codable {
    case generateMetrics = "generate-metrics"
    case logs
    case messageBatch = "message-batch"
    case appStarted = "app-started"
    case appHeartbeat = "app-heartbeat"
    case appClosing = "app-closing"
}

/// A single telemetry metric series for `generate-metrics`.
public struct TelemetryMetric: TelemetryPayload, Codable {
    /// Per-tracer metric namespace (`dd.instrumentation_telemetry_data.{namespace}.*`).
    public enum Namespace: String, Codable {
        case tracers, general, telemetry, iast, appsec
    }

    /// The metric kind. The intake defaults to `.gauge` when omitted.
    public enum MetricType: String, Codable {
        case gauge, count, rate
    }

    /// A single `[timestamp, value]` sample. Encoded as a JSON pair, per spec.
    public struct Point: Codable {
        public var timestamp: TimeInterval
        public var value: Double

        public init(timestamp: TimeInterval, value: Double) {
            self.timestamp = timestamp
            self.value = value
        }

        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            self.timestamp = try container.decode(TimeInterval.self)
            self.value = try container.decode(Double.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(timestamp)
            try container.encode(value)
        }
    }

    /// A metric series with one or more sampled points.
    public struct Series: Codable {
        public var metric: String
        public var points: [Point]
        public var interval: Double?
        public var type: MetricType?
        public var tags: [String]?
        public var common: Bool?
        /// Per-series override for the payload-level namespace.
        public var namespace: Namespace?

        public init(metric: String,
                    points: [Point],
                    interval: Double? = nil,
                    type: MetricType? = nil,
                    tags: [String]? = nil,
                    common: Bool? = nil,
                    namespace: Namespace? = nil)
        {
            self.metric = metric
            self.points = points
            self.interval = interval
            self.type = type
            self.tags = tags
            self.common = common
            self.namespace = namespace
        }
    }
    
    public var namespace: Namespace?
    public var series: [Series]
    
    public init(namespace: Namespace?, series: [Series]) {
        self.namespace = namespace
        self.series = series
    }
    
    public var requestType: TelemetryRequestType { .generateMetrics }
}

/// A single telemetry log message for the `logs` request type.
///
/// The telemetry intake's `log_message` schema is intentionally minimal — it
/// does *not* duplicate the service / env / host / version identity that the
/// outer envelope carries. This type is purpose-built for that endpoint and
/// is unrelated to `DDLog` (the `/api/v2/logs` body).
public struct TelemetryLog: Codable {
    public enum Level: String, Codable {
        case error = "ERROR"
        case warn = "WARN"
        case debug = "DEBUG"
    }

    public var message: String
    public var level: Level
    /// Deduplicated occurrence count. Optional per spec.
    public var count: Int?
    /// Comma-separated tag string in the form `"k:v,k:v"`. Optional.
    public var tags: String?
    public var stackTrace: String?
    /// Per-log unix-seconds timestamp. When `nil`, the envelope's `tracer_time` is used.
    public var tracerTime: Int64?
    
    public init(message: String,
                level: Level,
                count: Int? = nil,
                tags: String? = nil,
                stackTrace: String? = nil,
                tracerTime: Int64? = nil)
    {
        self.message = message
        self.level = level
        self.count = count
        self.tags = tags
        self.stackTrace = stackTrace
        self.tracerTime = tracerTime
    }

    enum CodingKeys: String, CodingKey {
        case message, level, count, tags
        case stackTrace = "stack_trace"
        case tracerTime = "tracer_time"
    }
    
    public struct Logs: TelemetryPayload, ExpressibleByArrayLiteral, Codable {
        public typealias ArrayLiteralElement = TelemetryLog
        
        public var logs: [TelemetryLog]
        
        public init(_ logs: [TelemetryLog]) {
            self.logs = logs
        }
        
        public init(arrayLiteral elements: TelemetryLog...) {
            self.logs = elements
        }
        
        public var requestType: TelemetryRequestType { .logs }
    }
}

// MARK: - App-lifecycle types

/// Lightweight error envelope used inside `app-started` (both at the payload
/// level and per-configuration-item).
public struct TelemetryError: Codable {
    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// Per-product status reported in `app-started`. All fields optional.
public struct TelemetryProductInfo: Codable {
    public var version: String?
    public var enabled: Bool?
    public var error: TelemetryError?

    public init(version: String? = nil,
                enabled: Bool? = nil,
                error: TelemetryError? = nil)
    {
        self.version = version
        self.enabled = enabled
        self.error = error
    }
}

/// Product-status payload inside `app-started`.
public struct TelemetryProducts: Codable {
    public var appsec: TelemetryProductInfo?
    public var profiler: TelemetryProductInfo?
    public var dynamicInstrumentation: TelemetryProductInfo?
    public var mlobs: TelemetryProductInfo?

    public init(appsec: TelemetryProductInfo? = nil,
                profiler: TelemetryProductInfo? = nil,
                dynamicInstrumentation: TelemetryProductInfo? = nil,
                mlobs: TelemetryProductInfo? = nil)
    {
        self.appsec = appsec
        self.profiler = profiler
        self.dynamicInstrumentation = dynamicInstrumentation
        self.mlobs = mlobs
    }

    enum CodingKeys: String, CodingKey {
        case appsec, profiler, mlobs
        case dynamicInstrumentation = "dynamic_instrumentation"
    }
}

/// Source of a `TelemetryConfigItem` value, per spec.
public enum TelemetryConfigOrigin: String, Codable {
    case envVar = "env_var"
    case jvmProp = "jvm_prop"
    case code
    case ddConfig = "dd_config"
    case remoteConfig = "remote_config"
    case appConfig = "app.config"
    case `default`
    case unknown
}

/// One entry in the `configuration` array of `app-started`.
/// `value` accepts string / number / boolean (per spec); use `JSONGeneric`
/// to model that union.
public struct TelemetryConfigItem: Codable {
    public var name: String
    public var value: JSONGeneric
    public var origin: TelemetryConfigOrigin
    public var error: TelemetryError?
    /// Optional monotonic counter the caller maintains per-config-key (or
    /// globally) to track the active set of values over time.
    public var seqId: UInt64?

    public init(name: String,
                value: JSONGeneric,
                origin: TelemetryConfigOrigin,
                error: TelemetryError? = nil,
                seqId: UInt64? = nil)
    {
        self.name = name
        self.value = value
        self.origin = origin
        self.error = error
        self.seqId = seqId
    }

    enum CodingKeys: String, CodingKey {
        case name, value, origin, error
        case seqId = "seq_id"
    }
}

/// `install_signature` block of `app-started`. Each field maps directly to
/// a `DD_INSTRUMENTATION_INSTALL_*` env-var per the spec.
public struct TelemetryInstallSignature: Codable {
    public var installId: String?
    public var installType: String?
    public var installTime: String?

    public init(installId: String? = nil,
                installType: String? = nil,
                installTime: String? = nil)
    {
        self.installId = installId
        self.installType = installType
        self.installTime = installTime
    }

    enum CodingKeys: String, CodingKey {
        case installId = "install_id"
        case installType = "install_type"
        case installTime = "install_time"
    }
}

/// Wire shape for `app-started` payload. All fields optional; `Encodable`
/// default behavior skips them when `nil`.
public struct TelemetryAppStarted: TelemetryPayload, Codable {
    var products: TelemetryProducts?
    var configuration: [TelemetryConfigItem]?
    var error: TelemetryError?
    var installSignature: TelemetryInstallSignature?
    
    public init(products: TelemetryProducts? = nil,
                configuration: [TelemetryConfigItem]? = nil,
                error: TelemetryError? = nil,
                installSignature: TelemetryInstallSignature? = nil)
    {
        self.products = products
        self.configuration = configuration
        self.error = error
        self.installSignature = installSignature
    }

    enum CodingKeys: String, CodingKey {
        case products, configuration, error
        case installSignature = "install_signature"
    }
    
    public var requestType: TelemetryRequestType { .appStarted }
}

public struct TelemetryAppHeartbeat: TelemetryPayload, Codable {
    public init() {}
    public var requestType: TelemetryRequestType { .appHeartbeat }
}

public struct TelemetryAppClosing: TelemetryPayload, Codable {
    public init() {}
    public var requestType: TelemetryRequestType { .appClosing }
}

public struct TelemetryMessageBatch: TelemetryPayload, Codable {
    public struct Message: Codable {
        var message: any TelemetryPayload
        
        enum CodingKeys: String, CodingKey {
            case requestType = "request_type"
            case payload
        }
        
        public init(_ message: any TelemetryPayload) {
            self.message = message
        }
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let requestType = try container.decode(TelemetryRequestType.self, forKey: .requestType)
            switch requestType {
            case .appStarted:
                message = try container.decode(TelemetryAppStarted.self, forKey: .payload)
            case .appHeartbeat:
                message = try container.decode(TelemetryAppHeartbeat.self, forKey: .payload)
            case .appClosing:
                message = try container.decode(TelemetryAppClosing.self, forKey: .payload)
            case .logs:
                message = try container.decode(TelemetryLog.Logs.self, forKey: .payload)
            case .generateMetrics:
                message = try container.decode(TelemetryMetric.self, forKey: .payload)
            case .messageBatch:
                message = try container.decode(TelemetryMessageBatch.self, forKey: .payload)
            }
        }
        
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message.requestType, forKey: .requestType)
            try container.encode(message, forKey: .payload)
        }
    }
    
    var messages: [any TelemetryPayload]
    
    public init(messages: [any TelemetryPayload]) {
        self.messages = messages
    }
    
    enum CodingKeys: String, CodingKey {
        case requestType = "request_type"
        case payload
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let messages = try container.decode([Message].self)
        self.messages = messages.map(\.message)
    }
    
    public func encode(to encoder: any Encoder) throws {
        let messages = self.messages.map(Message.init)
        var container = encoder.singleValueContainer()
        try container.encode(messages)
    }
    
    public var requestType: TelemetryRequestType { .messageBatch }
}

// MARK: - Protocol

public protocol TelemetryApi: APIService {
    /// Send the one-time `app-started` event. Per spec this should be sent
    /// exactly once per tracer lifecycle, after init. All payload fields are
    /// optional and `nil` ones are omitted from the wire payload.
    func sendAppStarted(products: TelemetryProducts?,
                        configuration: [TelemetryConfigItem]?,
                        error: TelemetryError?,
                        installSignature: TelemetryInstallSignature?) async throws(APICallError)

    /// Send an `app-heartbeat` event. Per spec callers should schedule this
    /// once per minute after `sendAppStarted` for as long as the app is alive,
    /// even if other telemetry events were sent in the same window.
    func sendAppHeartbeat() async throws(APICallError)

    /// Send the `app-closing` event when the app is about to terminate.
    /// Should use a short timeout so it doesn't delay shutdown.
    func sendAppClosing() async throws(APICallError)

    /// Send a batch of metric series via the `generate-metrics` request type.
    func sendMetrics(_ series: [TelemetryMetric.Series],
                     namespace: TelemetryMetric.Namespace?) async throws(APICallError)

    /// Send a batch of log messages via the `logs` request type.
    func sendLogs(_ logs: [TelemetryLog]) async throws(APICallError)

    /// Send a mixed batch of telemetry items via the `message-batch` request
    /// type. Items keep their original request_type tag inside the batch and
    /// share the outer envelope's `application`/`host`/`runtime_id`/`seq_id`.
    /// An empty `items` array is a no-op and does not hit the network.
    func send(batch items: [any TelemetryPayload]) async throws(APICallError)

    /// Send a batch of pre-encoded `TelemetryBatchEntry` values stored in a
    /// file. The file must contain one or more JSON-encoded batch entries
    /// separated by commas with no surrounding array brackets — the format
    /// written by `TelemetryExporter`. The service wraps them with a fresh
    /// `message-batch` envelope (current timestamp, next `seq_id`, full
    /// `application` / `host` identity) before POSTing.
    func send(batch url: URL) async throws(APICallError)

    /// Send a batch of pre-encoded `TelemetryBatchEntry` values. `data` must
    /// contain one or more JSON-encoded batch entries separated by commas with
    /// no surrounding array brackets — the format written by
    /// `TelemetryExporter`. The service wraps them with a fresh
    /// `message-batch` envelope (current timestamp, next `seq_id`, full
    /// `application` / `host` identity) before POSTing.
    func send(batch data: Data) async throws(APICallError)
}

extension TelemetryApi {
    public func send(batch url: URL) async throws(APICallError) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw .fileSystem(error)
        }
        try await send(batch: data)
    }
}

// MARK: - Service

internal struct TelemetryApiService: TelemetryApi {
    var endpoint: Endpoint
    var headers: [HTTPHeader]
    var encoder: JSONEncoder
    var decoder: JSONDecoder
    let compression: Bool
    let httpClient: HTTPClient
    let log: Logger
    let dateProvider: DateProvider

    /// Stable identifier for this tracer session. Reused as the telemetry
    /// `runtime_id` so backend can correlate telemetry with traces.
    private let runtimeId: String
    private let application: TelemetryApplication
    private let host: TelemetryHost
    /// Strictly monotonic `seq_id` counter. The intake uses gaps in this
    /// sequence to detect dropped messages, so it must increase across all
    /// telemetry requests within a runtime.
    private let seq: Synced<UInt64>

    init(config: APIServiceConfig, httpClient: HTTPClient, dateProvider: DateProvider, log: Logger) {
        self.endpoint = config.endpoint
        self.httpClient = httpClient
        self.log = log
        self.dateProvider = dateProvider
        // The telemetry intake does NOT accept the trace-style headers — strip
        // them. Keep the auth / user-agent / hostname additions.
        self.headers = config.defaultHeaders.filter { header in
            switch header.field {
            case .traceIDHeaderField, .parentSpanIDHeaderField, .samplingPriorityHeaderField:
                return false
            default:
                return true
            }
        }
        self.compression = config.payloadCompression
        self.encoder = config.encoder
        self.decoder = config.decoder
        self.runtimeId = config.clientId
        self.application = TelemetryApplication(config: config)
        self.host = TelemetryHost(config: config)
        self.seq = Synced<UInt64>(0)
    }

    func sendAppStarted(products: TelemetryProducts?,
                        configuration: [TelemetryConfigItem]?,
                        error: TelemetryError?,
                        installSignature: TelemetryInstallSignature?) async throws(APICallError)
    {
        let payload = TelemetryAppStarted(products: products, configuration: configuration,
                                          error: error, installSignature: installSignature)
        try await send(payload: payload)
    }

    func sendAppHeartbeat() async throws(APICallError) {
        try await send(payload: TelemetryAppHeartbeat())
    }

    func sendAppClosing() async throws(APICallError) {
        try await send(payload: TelemetryAppClosing())
    }

    func sendMetrics(_ series: [TelemetryMetric.Series],
                     namespace: TelemetryMetric.Namespace?) async throws(APICallError)
    {
        let payload = TelemetryMetric(namespace: namespace, series: series)
        try await send(payload: payload)
    }

    func sendLogs(_ logs: [TelemetryLog]) async throws(APICallError) {
        guard !logs.isEmpty else { return }
        try await send(payload: TelemetryLog.Logs(logs))
    }

    func send(batch items: [any TelemetryPayload]) async throws(APICallError) {
        guard !items.isEmpty else { return }
        try await send(payload: TelemetryMessageBatch(messages: items))
    }

    func send(batch data: Data) async throws(APICallError) {
        // Wrap the raw comma-separated batch entries with a fresh envelope:
        // prefix = {"api_version":…,"payload":[ and suffix = ]}
        let header = makeEnvelope(payload: TelemetryVoidBatch())
        let dataFormat: DataFormat
        do {
            dataFormat = try DataFormat(header: header, encoder: encoder)
        } catch {
            throw .transport(error)
        }
        try await send(requestType: .messageBatch,
                       body: dataFormat.prefix + data + dataFormat.suffix)
    }

    var endpointURLs: Set<URL> { [endpoint.telemetryURL] }
    
    private func nextSeqId() -> UInt64 {
        seq.update { value in
            value &+= 1
            return value
        }
    }
    
    private func makeEnvelope<Payload: TelemetryPayload>(payload: Payload) -> TelemetryEnvelope<Payload> {
        TelemetryEnvelope(
            requestType: payload.requestType,
            tracerTime: UInt64(dateProvider.currentDate().timeIntervalSince1970),
            runtimeId: runtimeId,
            seqId: nextSeqId(),
            application: application,
            host: host,
            payload: payload
        )
    }

    private func send<Payload: TelemetryPayload>(payload: Payload) async throws(APICallError) {
        let envelope = makeEnvelope(payload: payload)
        let data: Data
        do {
            data = try encoder.encode(envelope)
        } catch let err as EncodingError {
            throw .encoding(value: envelope, error: err)
        } catch {
            throw .unknownError(error)
        }
        try await send(requestType: payload.requestType, body: data)
    }

    private func send(requestType: TelemetryRequestType,
                      body: Data) async throws(APICallError)
    {
        var request = URLRequest(url: endpoint.telemetryURL)
        request.httpMethod = "POST"
        request.httpHeaders = headers
        request.setHTTPHeader(.contentTypeHeader(contentType: .applicationJSON))
        request.setValue(.constant(TelemetryHeaders.apiVersion),
                         forHTTPHeader: .ddTelemetryApiVersion)
        request.setValue(.constant(requestType.rawValue),
                         forHTTPHeader: .ddTelemetryRequestType)
        request.setValue(.constant(TelemetryHeaders.libraryLanguage),
                         forHTTPHeader: .ddClientLibraryLanguage)
        request.setValue(.constant(application.tracerVersion),
                         forHTTPHeader: .ddClientLibraryVersion)
        if compression {
            request.setHTTPHeader(.contentEncodingHeader(contentEncoding: .deflate))
        }
        request.httpBody = body

        let log = self.log
        log.debug("Telemetry \(requestType.rawValue) sending \(body.count) bytes...")
        let _ = try await httpClient.send(api: request)
        log.debug("Telemetry \(requestType.rawValue) accepted")
    }
}

// MARK: - Wire types

internal struct TelemetryEnvelope<Payload: Encodable>: Encodable {
    let apiVersion: String = TelemetryHeaders.apiVersion
    let requestType: TelemetryRequestType
    let tracerTime: UInt64
    let runtimeId: String
    let seqId: UInt64
    let application: TelemetryApplication
    let host: TelemetryHost
    let payload: Payload

    enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case requestType = "request_type"
        case tracerTime = "tracer_time"
        case runtimeId = "runtime_id"
        case seqId = "seq_id"
        case application
        case host
        case payload
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(apiVersion, forKey: .apiVersion)
        try c.encode(requestType, forKey: .requestType)
        try c.encode(tracerTime, forKey: .tracerTime)
        try c.encode(runtimeId, forKey: .runtimeId)
        try c.encode(seqId, forKey: .seqId)
        try c.encode(application, forKey: .application)
        try c.encode(host, forKey: .host)
        if payload as? any APIVoidValue == nil {
            try c.encode(payload, forKey: .payload)
        }
    }
}

extension TelemetryEnvelope: JSONFileHeader {
    static var batchFieldName: String { "payload" }
}

internal struct TelemetryApplication: Encodable {
    let serviceName: String
    let env: String
    let serviceVersion: String
    let tracerVersion: String
    let languageName: String
    let languageVersion: String
    let runtimeName: String
    let runtimeVersion: String

    init(config: APIServiceConfig) {
        self.serviceName = config.serviceName
        self.env = config.environment
        self.serviceVersion = config.version
        self.tracerVersion = config.version
        self.languageName = TelemetryHeaders.libraryLanguage
        self.languageVersion = SwiftRuntime.languageVersion
        self.runtimeName = "swift"
        self.runtimeVersion = SwiftRuntime.languageVersion
    }

    enum CodingKeys: String, CodingKey {
        case serviceName = "service_name"
        case env
        case serviceVersion = "service_version"
        case tracerVersion = "tracer_version"
        case languageName = "language_name"
        case languageVersion = "language_version"
        case runtimeName = "runtime_name"
        case runtimeVersion = "runtime_version"
    }
}

internal struct TelemetryHost: Encodable {
    let hostname: String
    let os: String
    let osVersion: String
    let architecture: String
    let kernelName: String
    let kernelRelease: String
    let kernelVersion: String

    init(config: APIServiceConfig) {
        let kernel = SwiftRuntime.kernelInfo
        self.hostname = config.hostname ?? ProcessInfo.processInfo.hostName
        self.os = config.device.osName
        self.osVersion = config.device.osVersion
        self.architecture = kernel.machine
        self.kernelName = kernel.sysname
        self.kernelRelease = kernel.release
        self.kernelVersion = kernel.version
    }

    enum CodingKeys: String, CodingKey {
        case hostname, os, architecture
        case osVersion = "os_version"
        case kernelName = "kernel_name"
        case kernelRelease = "kernel_release"
        case kernelVersion = "kernel_version"
    }
}

// MARK: - Helpers

private struct TelemetryVoidBatch: TelemetryPayload, APIVoidValue, Encodable {
    var requestType: TelemetryRequestType { .messageBatch }
    static var void: TelemetryVoidBatch { .init() }
}

private enum TelemetryHeaders {
    static let apiVersion = "v2"
    static let libraryLanguage = "swift"
}

extension HTTPHeader.Field {
    static let ddTelemetryApiVersion: Self = "DD-Telemetry-API-Version"
    static let ddTelemetryRequestType: Self = "DD-Telemetry-Request-Type"
    static let ddClientLibraryLanguage: Self = "DD-Client-Library-Language"
    static let ddClientLibraryVersion: Self = "DD-Client-Library-Version"
}

private enum SwiftRuntime {
    struct KernelInfo {
        let sysname: String
        let release: String
        let version: String
        let machine: String
    }

    /// Cached result of `uname(3)` for the host this process runs on.
    /// Populated lazily; safe to read concurrently because the closure body
    /// runs at most once and the resulting struct is value-typed.
    static let kernelInfo: KernelInfo = {
        var info = utsname()
        guard uname(&info) == 0 else {
            return KernelInfo(sysname: "", release: "", version: "", machine: "")
        }
        return KernelInfo(sysname: cString(&info.sysname),
                          release: cString(&info.release),
                          version: cString(&info.version),
                          machine: cString(&info.machine))
    }()

    static let languageVersion: String = {
        #if swift(>=6.2)
        return "6.2"
        #elseif swift(>=6.1)
        return "6.1"
        #elseif swift(>=6.0)
        return "6.0"
        #elseif swift(>=5.10)
        return "5.10"
        #elseif swift(>=5.9)
        return "5.9"
        #else
        return ""
        #endif
    }()

    /// Read a C `char[N]` tuple (which is how `utsname` fields surface to
    /// Swift) as a null-terminated `String`.
    private static func cString<T>(_ pointer: UnsafePointer<T>) -> String {
        pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
            String(cString: $0)
        }
    }
}

// MARK: - Endpoint URL

private extension Endpoint {
    var telemetryURL: URL {
        let endpoint = "/api/v2/apmtelemetry"
        switch self {
        case let .other(testsBaseURL: url, logsBaseURL: _):
            return url.appendingPathComponent(endpoint)
        default:
            return URL(string: "https://instrumentation-telemetry-intake.\(site!)\(endpoint)")!
        }
    }
}
