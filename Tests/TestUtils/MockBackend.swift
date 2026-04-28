/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2025-Present Datadog, Inc.
 */

import Compression
import Foundation

// MARK: - MockBackend

/// A mock HTTP backend that handles all Datadog SDK exporter endpoints.
/// Stores received payloads and returns configurable responses so integration
/// tests can verify SDK behaviour end-to-end without hitting real Datadog servers.
///
/// Usage:
/// ```swift
/// let backend = MockBackend()
/// try backend.start()
/// // Configure endpoint in your SDK: .other(testsBaseURL: backend.baseURL, logsBaseURL: backend.baseURL)
/// // ... run tests ...
/// backend.waitForSpans()
/// let spans = backend.requests.allSpans
/// backend.stop()
/// ```
public final class MockBackend {
    public struct Config: Sendable {
        /// Returned for POST /api/v2/libraries/tests/services/setting
        public var settings: Settings
        /// Returned for POST /api/v2/ci/libraries/tests
        public var knownTests: KnownTestsMap
        /// Returned for POST /api/v2/ci/tests/skippable
        public var skippableTests: [SkippableTest]
        /// Correlation ID included in the skippable tests response.
        public var skippableTestsCorrelationId: String
        /// Returned for GET /api/v2/test/libraries/test-management/tests
        public var testManagement: TestManagementMap
        
        public init(settings: Settings = .init(),
                    knownTests: KnownTestsMap = [:],
                    skippableTests: [SkippableTest] = [],
                    skippableTestsCorrelationId: String = "mock-correlation-id",
                    testManagement: TestManagementMap = [:])
        {
            self.settings = settings
            self.knownTests = knownTests
            self.skippableTests = skippableTests
            self.skippableTestsCorrelationId = skippableTestsCorrelationId
            self.testManagement = testManagement
        }
    }

    public struct Requests: Sendable {
        /// All decoded span envelopes received so far.
        public var spanEnvelopes: [SpanEnvelope] = []
        /// All log batches received so far.
        public var logs: [[Log]] = []
        /// All decoded coverage payloads received so far.
        public var coverage: [CoveragePayload] = []
        /// Raw bodies of all settings requests made by the SDK.
        public var settings: [Data] = []
        /// Raw bodies of all known-tests requests.
        public var knownTests: [Data] = []
        /// Raw bodies of all skippable-tests requests.
        public var skippableTests: [Data] = []
        /// Raw bodies of all test-management requests.
        public var testManagement: [Data] = []
        /// Raw bodies of all git search-commits requests.
        public var searchCommits: [Data] = []
        /// All packfiles received so far.
        public var packfile: [Data] = []

        /// All spans across all received envelopes.
        public var allSpans: [Span] { spanEnvelopes.flatMap(\.allSpans) }
        /// All spans across all received envelopes.
        public var allInfoSpans: [Span] { spanEnvelopes.flatMap(\.infoSpans) }
        /// All test-type spans across all received envelopes.
        public var allTestSpans: [Span] { spanEnvelopes.flatMap(\.testSpans) }

        /// All individual log entries across all batches.
        public var allLogs: [Log] { logs.flatMap { $0 } }

        /// All individual coverage entries across all payloads.
        public var allCoverages: [TestCoverage] { coverage.flatMap(\.coverages) }
    }
    
    // Thread safety.
    private let _lock = NSLock()

    // MARK: - Configuration (thread-safe read via computed property)
    private var _configuration: Config = .init()
    public var configuration: Config {
        get { _lock.withLock { _configuration } }
        set { _lock.withLock { _configuration = newValue } }
    }

    // MARK: - Received Data (thread-safe read via computed property)
    private var _requests: Requests = .init()
    public var requests: Requests { _lock.withLock { _requests } }

    // MARK: - Server

    private var _server: HttpTestServer!

    public var serverPort: Int { _server.serverPort }

    /// Base URL for this backend, e.g. `http://127.0.0.1:12345`.
    /// Pass this to `Endpoint.other(testsBaseURL:logsBaseURL:)` when configuring the SDK.
    public var baseURL: URL { _server.baseURL }

    public init() {}
    deinit { stop() }

    // MARK: - Lifecycle

    public func start() throws {
        _server = .init() { [weak self] request, response in
            guard let self else {
                response.sendResponse(status: .internalServerError,
                                      contentType: "application/json",
                                      body: Data("{}".utf8))
                return
            }
            let res = self.route(request: request)
            response.sendResponse(status: res.status, contentType: res.contentType, body: res.body)
        }
        try _server.start()
    }

    public func stop() {
        guard let _server else { return }
        _server.stop()
        self._server = nil
    }

    /// Clears all received data without affecting configuration.
    public func reset() {
        _lock.withLock { _requests = .init() }
    }

    // MARK: - Wait Helpers

    /// Blocks until at least `count` span envelopes have been received, or `timeout` elapses.
    @discardableResult
    public func waitForSpans(count: Int = 1, timeout: TimeInterval = 10) -> Bool {
        poll(timeout: timeout) { self._lock.withLock { self._requests.spanEnvelopes.count >= count } }
    }

    /// Blocks until at least `count` log batches have been received, or `timeout` elapses.
    @discardableResult
    public func waitForLogs(count: Int = 1, timeout: TimeInterval = 10) -> Bool {
        poll(timeout: timeout) { self._lock.withLock { self._requests.logs.count >= count } }
    }

    /// Blocks until at least `count` coverage payloads have been received, or `timeout` elapses.
    @discardableResult
    public func waitForCoverage(count: Int = 1, timeout: TimeInterval = 10) -> Bool {
        poll(timeout: timeout) { self._lock.withLock { self._requests.coverage.count >= count } }
    }

    /// Blocks until at least `count` settings requests have been received, or `timeout` elapses.
    @discardableResult
    public func waitForSettings(count: Int = 1, timeout: TimeInterval = 10) -> Bool {
        poll(timeout: timeout) { self._lock.withLock { self._requests.settings.count >= count } }
    }

    private func poll(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition()
    }

    // MARK: - Routing

    private func route(request: HTTPTestRequest) -> (status: HTTPTestResponseSender.Status, contentType: String, body: Data) {
        let body = request.head.headers.first(name: "content-encoding")?.lowercased() == "deflate"
            ? (request.body._zlibInflated ?? request.body) : request.body
        switch request.head.path {
        case "/api/v2/citestcycle":
            if let envelope = try? JSONDecoder().decode(SpanEnvelope.self, from: body) {
                _lock.withLock { _requests.spanEnvelopes.append(envelope) }
            }
            return (.ok, "application/json", Data("{}".utf8))

        case "/api/v2/logs":
            if let logs = try? JSONDecoder().decode([Log].self, from: body) {
                _lock.withLock { _requests.logs.append(logs) }
            }
            return (.ok, "application/json", Data("{}".utf8))

        case "/api/v2/citestcov":
            if let payload = parseCoveragePayload(headers: request.head.headers, rawBody: request.body) {
                _lock.withLock { _requests.coverage.append(payload) }
            }
            return (.ok, "application/json", Data("{}".utf8))

        case "/api/v2/libraries/tests/services/setting":
            _lock.withLock { _requests.settings.append(body) }
            return (.ok, "application/json", buildSettingsResponse())

        case "/api/v2/ci/libraries/tests":
            _lock.withLock { _requests.knownTests.append(body) }
            return (.ok, "application/json", buildKnownTestsResponse())

        case "/api/v2/ci/tests/skippable":
            _lock.withLock { _requests.skippableTests.append(body) }
            return (.ok, "application/json", buildSkippableTestsResponse())

        case "/api/v2/git/repository/search_commits":
            _lock.withLock { _requests.searchCommits.append(body) }
            return (.ok, "application/json", Data("{\"data\":[]}".utf8))

        case "/api/v2/git/repository/packfile":
            _lock.withLock { _requests.packfile.append(body) }
            return (.ok, "application/json", Data("{}".utf8))

        case "/api/v2/test/libraries/test-management/tests":
            _lock.withLock { _requests.testManagement.append(body) }
            return (.ok, "application/json", buildTestManagementResponse())

        default:
            return (.notFound, "application/json", Data("{}".utf8))
        }
    }

    // MARK: - Response Builders

    private func buildSettingsResponse() -> Data {
        let s = configuration.settings
        let payload: [String: Any] = [
            "data": [
                "id": "1",
                "type": "ci_app_tracers_test_service_settings",
                "attributes": [
                    "itr_enabled": s.itrEnabled,
                    "code_coverage": s.codeCoverage,
                    "tests_skipping": s.testsSkipping,
                    "known_tests_enabled": s.knownTestsEnabled,
                    "require_git": s.requireGit,
                    "flaky_test_retries_enabled": s.flakyTestRetriesEnabled,
                    "early_flake_detection": [
                        "enabled": s.earlyFlakeDetection.enabled,
                        "slow_test_retries": s.earlyFlakeDetection.slowTestRetries,
                        "faulty_session_threshold": s.earlyFlakeDetection.faultySessionThreshold
                    ] as [String: Any],
                    "test_management": [
                        "enabled": s.testManagement.enabled,
                        "attempt_to_fix_retries": s.testManagement.attemptToFixRetries
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private func buildKnownTestsResponse() -> Data {
        let knownTests = configuration.knownTests
        let totalTests = knownTests.values.flatMap { $0.values }.flatMap { $0 }.count
        let payload: [String: Any] = [
            "data": [
                "id": "1",
                "type": "ci_app_libraries_tests",
                "attributes": [
                    "tests": knownTests,
                    "page_info": [
                        "cursor": NSNull(),
                        "size": totalTests,
                        "has_next": false
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private func buildSkippableTestsResponse() -> Data {
        let dataArray: [[String: Any]] = configuration.skippableTests.enumerated().map { idx, test in
            [
                "type": "test",
                "id": "\(idx + 1)",
                "attributes": [
                    "name": test.name,
                    "suite": test.suite,
                    "parameters": NSNull(),
                    "configurations": NSNull()
                ] as [String: Any]
            ]
        }
        let payload: [String: Any] = [
            "meta": ["correlation_id": configuration.skippableTestsCorrelationId],
            "data": dataArray
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private func buildTestManagementResponse() -> Data {
        var modulesDict: [String: Any] = [:]
        for (moduleName, suites) in configuration.testManagement {
            var suitesDict: [String: Any] = [:]
            for (suiteName, tests) in suites {
                var testsDict: [String: Any] = [:]
                for (testName, props) in tests {
                    testsDict[testName] = [
                        "properties": [
                            "disabled": props.disabled,
                            "quarantined": props.quarantined,
                            "attempt_to_fix": props.attemptToFix
                        ] as [String: Any]
                    ]
                }
                suitesDict[suiteName] = ["tests": testsDict]
            }
            modulesDict[moduleName] = ["suites": suitesDict]
        }
        let payload: [String: Any] = [
            "data": [
                "id": "1",
                "type": "ci_app_libraries_tests",
                "attributes": ["modules": modulesDict]
            ] as [String: Any]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    // MARK: - Coverage Multipart Parser

    /// Extracts the "coverage" field from a multipart/form-data request and decodes it.
    private func parseCoveragePayload(headers: HTTPTestRequest.Headers, rawBody: Data) -> CoveragePayload? {
        guard let contentType = headers.first(name: "content-type"),
              contentType.lowercased().contains("multipart/form-data"),
              let boundaryRange = contentType.range(of: "boundary=", options: .caseInsensitive)
        else { return nil }

        // Boundary may be quoted or unquoted; strip trailing parameters after ";"
        var boundary = String(contentType[boundaryRange.upperBound...])
            .components(separatedBy: ";").first ?? ""
        boundary = boundary.trimmingCharacters(in: .whitespaces)
        if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
            boundary = String(boundary.dropFirst().dropLast())
        }
        guard !boundary.isEmpty else { return nil }

        guard let json = extractMultipartField(named: "coverage", from: rawBody, boundary: boundary)
        else { return nil }

        return try? JSONDecoder().decode(CoveragePayload.self, from: json)
    }

    /// Scans a raw multipart body and returns the data for the named field.
    private func extractMultipartField(named fieldName: String, from body: Data, boundary: String) -> Data? {
        guard let partDelim = ("--" + boundary + "\r\n").data(using: .utf8),
              let headerBodySep = "\r\n\r\n".data(using: .utf8),
              let bodyEndMark = ("\r\n--" + boundary).data(using: .utf8)
        else { return nil }

        var pos = body.startIndex
        while pos < body.endIndex {
            guard let delimRange = body.range(of: partDelim, in: pos..<body.endIndex) else { break }
            let headersStart = delimRange.upperBound

            guard let sepRange = body.range(of: headerBodySep, in: headersStart..<body.endIndex) else { break }

            let headerBytes = body.subdata(in: headersStart..<sepRange.lowerBound)
            guard let headerStr = String(data: headerBytes, encoding: .utf8) else {
                pos = sepRange.upperBound; continue
            }

            let isTarget = headerStr.components(separatedBy: "\r\n").contains { line in
                let l = line.lowercased()
                return l.contains("content-disposition") && l.contains("name=\"\(fieldName)\"")
            }

            let bodyStart = sepRange.upperBound
            let bodyEnd: Data.Index
            if let endRange = body.range(of: bodyEndMark, in: bodyStart..<body.endIndex) {
                bodyEnd = endRange.lowerBound
            } else {
                bodyEnd = body.endIndex
            }

            if isTarget { return body.subdata(in: bodyStart..<bodyEnd) }
            pos = bodyEnd
        }
        return nil
    }
}

// MARK: - Decoded Span Types

extension MockBackend {
    /// Top-level envelope sent to /api/v2/citestcycle.
    public struct SpanEnvelope: Decodable, Sendable {
        public let version: Int
        public let metadata: [String: [String: String]]
        public let events: [SpanEvent]
        
        var extended: [SpanEvent] { events.map { $0.extend(metadata: metadata) } }
        
        /// All span payloads from all events.
        public var allSpans: [Span] { extended.compactMap(\.span) }
        /// Only events with type == "span"
        public var infoSpans: [Span] { extended.filter { $0.isSpan }.compactMap(\.span) }
        /// Only events with type == "test".
        public var testSpans: [Span] { extended.filter { $0.isTest }.compactMap(\.span) }
        /// Only end events
        public var testEvents: [TestSpan] { extended.filter { $0.isEvent }.compactMap(\.event) }
    }
    
    public enum SpanEvent: Decodable, Sendable {
        case span(Span)
        case test(Span)
        case suiteEnd(TestSpan)
        case moduleEnd(TestSpan)
        case sessionEnd(TestSpan)
        
        var isTest: Bool {
            switch self {
            case .test: return true
            default: return false
            }
        }
        
        var isSpan: Bool {
            switch self {
            case .span: return true
            default: return false
            }
        }
        
        var isEvent: Bool {
            switch self {
            case .moduleEnd, .suiteEnd, .sessionEnd: return true
            default: return false
            }
        }
        
        var span: Span? {
            switch self {
            case .span(let span), .test(let span): return span
            default: return nil
            }
        }
        
        var event: TestSpan? {
            switch self {
            case .moduleEnd(let event), .suiteEnd(let event), .sessionEnd(let event): return event
            default: return nil
            }
        }
        
        struct Wrapper<T: Decodable>: Decodable {
            let type: String
            let version: Int
            let content: T
        }
        
        struct Header: Decodable {
            let type: String
            let version: Int
        }
        
        enum CodingKeys: String, CodingKey {
            case span
            case test
            case suiteEnd = "test_suite_end"
            case moduleEnd = "test_module_end"
            case sessionEnd = "test_session_end"
        }
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let header = try container.decode(Header.self)
            
            guard let type = CodingKeys(rawValue: header.type) else {
                throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                        debugDescription: "Unknown type: \(header.type)"))
            }
            
            switch type {
            case .span:
                let envelope = try container.decode(Wrapper<Span>.self)
                guard envelope.version == 1 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                            debugDescription: "Unsupported version: \(envelope.version)"))
                }
                self = .span(envelope.content)
            case .test:
                let envelope = try container.decode(Wrapper<Span>.self)
                guard envelope.version == 2 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                            debugDescription: "Unsupported version: \(envelope.version)"))
                }
                self = .test(envelope.content)
            case .suiteEnd:
                let envelope = try container.decode(Wrapper<TestSpan>.self)
                guard envelope.version == 1 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                            debugDescription: "Unsupported version: \(envelope.version)"))
                }
                self = .suiteEnd(envelope.content)
            case .moduleEnd:
                let envelope = try container.decode(Wrapper<TestSpan>.self)
                guard envelope.version == 1 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                            debugDescription: "Unsupported version: \(envelope.version)"))
                }
                self = .moduleEnd(envelope.content)
            case .sessionEnd:
                let envelope = try container.decode(Wrapper<TestSpan>.self)
                guard envelope.version == 1 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                            debugDescription: "Unsupported version: \(envelope.version)"))
                }
                self = .sessionEnd(envelope.content)
            }
        }
        
        func extend(metadata: borrowing [String: [String: String]]) -> Self {
            switch self {
            case .span(let span): return .span(span.extend(metadata: metadata))
            case .test(let span): return .test(span.extend(metadata: metadata))
            case .suiteEnd(let event): return .suiteEnd(event.extend(type: CodingKeys.suiteEnd.rawValue,
                                                                     metadata: metadata))
            case .moduleEnd(let event): return .moduleEnd(event.extend(type: CodingKeys.moduleEnd.rawValue,
                                                                       metadata: metadata))
            case .sessionEnd(let event): return .sessionEnd(event.extend(type: CodingKeys.sessionEnd.rawValue,
                                                                         metadata: metadata))
            }
        }
    }
    
    public struct Span: Decodable, Sendable {
        public let traceId: UInt64
        public let spanId: UInt64
        public let parentId: UInt64
        public let testSessionId: UInt64?
        public let testModuleId: UInt64?
        public let testSuiteId: UInt64?
        public let name: String
        public let service: String
        public let resource: String
        public let type: String
        public let start: UInt64
        public let duration: UInt64
        public let error: Int
        public let meta: [String: String]
        public let metrics: [String: Double]
        public let itrCorrelationId: String?
        
        enum CodingKeys: String, CodingKey {
            case traceId = "trace_id"
            case spanId = "span_id"
            case parentId = "parent_id"
            case testSessionId = "test_session_id"
            case testModuleId = "test_module_id"
            case testSuiteId = "test_suite_id"
            case name, service, resource, type, start, duration, error, meta, metrics
            case itrCorrelationId = "itr_correlation_id"
        }
        
        func extend(metadata: borrowing [String: [String: String]]) -> Self {
            var meta = self.meta
            if let typed = metadata[type] {
                meta.merge(typed) { a, b in a }
            }
            if let common = metadata["*"] {
                meta.merge(common) { a, b in a }
            }
            return .init(traceId: traceId, spanId: spanId, parentId: parentId,
                         testSessionId: testSessionId, testModuleId: testModuleId,
                         testSuiteId: testSuiteId, name: name, service: service,
                         resource: resource, type: type, start: start, duration: duration,
                         error: error, meta: meta, metrics: metrics, itrCorrelationId: itrCorrelationId)
        }
    }
    
    public struct TestSpan: Decodable, Sendable {
        public let testSessionId: UInt64
        public let testModuleId: UInt64?
        public let testSuiteId: UInt64?
        public let name: String
        public let service: String
        public let resource: String
        public let start: UInt64
        public let duration: UInt64
        public let error: Int
        public let meta: [String: String]
        public let metrics: [String: Double]
        
        enum CodingKeys: String, CodingKey {
            case testSessionId = "test_session_id"
            case testModuleId = "test_module_id"
            case testSuiteId = "test_suite_id"
            case name, service, resource, start, duration, error, meta, metrics
        }
        
        func extend(type: String, metadata: borrowing [String: [String: String]]) -> Self {
            var meta = self.meta
            if let typed = metadata[type] {
                meta.merge(typed) { a, b in a }
            }
            if let common = metadata["*"] {
                meta.merge(common) { a, b in a }
            }
            return .init(testSessionId: testSessionId, testModuleId: testModuleId,
                         testSuiteId: testSuiteId, name: name, service: service,
                         resource: resource, start: start, duration: duration,
                         error: error, meta: meta, metrics: metrics)
        }
    }
}

// MARK: - Decoded Coverage Types

extension MockBackend {
    /// Top-level payload received at /api/v2/citestcov (extracted from the "coverage" multipart field).
    public struct CoveragePayload: Decodable, Sendable {
        public let version: Int
        public let coverages: [TestCoverage]
    }
    
    /// Per-test coverage entry within a payload.
    public struct TestCoverage: Decodable, Sendable {
        public let testSessionId: UInt64
        public let testSuiteId: UInt64
        public let spanId: UInt64
        public let files: [CoverageFile]
        
        enum CodingKeys: String, CodingKey {
            case testSessionId = "test_session_id"
            case testSuiteId = "test_suite_id"
            case spanId = "span_id"
            case files
        }
    }
    
    /// A covered-file entry. `bitmap` is a bit-per-line coverage mask, base64-decoded from JSON.
    public struct CoverageFile: Decodable, Sendable {
        public let filename: String
        public let bitmap: Data
        
        /// Returns the set of 1-based line numbers that are marked as covered in the bitmap.
        public var coveredLines: IndexSet {
            var result = IndexSet()
            for (byteIdx, byte) in bitmap.enumerated() {
                for bit in 0..<8 {
                    if byte & (1 << (7 - bit)) != 0 {
                        result.insert(byteIdx * 8 + bit + 1)
                    }
                }
            }
            return result
        }
    }
}

// MARK: - Decoded Log Types

extension MockBackend {
    /// A single log entry received at /api/v2/logs.
    public struct Log: Decodable, Sendable {
        public let fields: [String: JSONValue]
        
        public subscript(key: String) -> JSONValue? { fields[key] }
        
        public var message: String? { fields["message"]?.stringValue }
        public var status: String? { fields["status"]?.stringValue }
        public var service: String? { fields["service"]?.stringValue }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: _DynamicKey.self)
            var fields: [String: JSONValue] = [:]
            for key in container.allKeys {
                fields[key.stringValue] = (try? container.decode(JSONValue.self, forKey: key)) ?? .null
            }
            self.fields = fields
        }
    }
    
    /// A flexible JSON value used in log fields.
    public enum JSONValue: Decodable, Sendable, CustomStringConvertible {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
        
        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            // Bool must be checked before Double since Bool is a subtype in some decoders
            if let v = try? c.decode(Bool.self) { self = .bool(v); return }
            if let v = try? c.decode(Double.self) { self = .number(v); return }
            if let v = try? c.decode(String.self) { self = .string(v); return }
            self = .null
        }
        
        public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
        public var numberValue: Double? { if case .number(let v) = self { return v }; return nil }
        public var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
        
        public var description: String {
            switch self {
            case .string(let v): return v
            case .number(let v): return "\(v)"
            case .bool(let v): return "\(v)"
            case .null: return "null"
            }
        }
    }
}

// MARK: - Mock Configuration Types
extension MockBackend {
    /// Configure the settings response returned to the SDK.
    public struct Settings: Sendable {
        public var itrEnabled: Bool
        public var codeCoverage: Bool
        public var testsSkipping: Bool
        public var knownTestsEnabled: Bool
        public var requireGit: Bool
        public var flakyTestRetriesEnabled: Bool
        public var earlyFlakeDetection: EFDConfig
        public var testManagement: TestManagementConfig

        public init(
            itrEnabled: Bool = false, codeCoverage: Bool = false, testsSkipping: Bool = false,
            knownTestsEnabled: Bool = false, requireGit: Bool = false, flakyTestRetriesEnabled: Bool = false,
            earlyFlakeDetection: EFDConfig = .init(), testManagement: TestManagementConfig = .init()
        ) {
            self.itrEnabled = itrEnabled; self.codeCoverage = codeCoverage
            self.testsSkipping = testsSkipping; self.knownTestsEnabled = knownTestsEnabled
            self.requireGit = requireGit; self.flakyTestRetriesEnabled = flakyTestRetriesEnabled
            self.earlyFlakeDetection = earlyFlakeDetection; self.testManagement = testManagement
        }
    }

    /// Early Flake Detection configuration returned in settings.
    public struct EFDConfig: Sendable {
        public var enabled: Bool
        public var slowTestRetries: [String: UInt]  // e.g. ["5s": 3, "1m": 1]
        public var faultySessionThreshold: Double

        public init(enabled: Bool = false, slowTestRetries: [String: UInt] = [:],
                    faultySessionThreshold: Double = 1.0) {
            self.enabled = enabled; self.slowTestRetries = slowTestRetries
            self.faultySessionThreshold = faultySessionThreshold
        }
    }

    /// Test Management configuration returned in settings.
    public struct TestManagementConfig: Sendable {
        public var enabled: Bool
        public var attemptToFixRetries: UInt

        public init(enabled: Bool = false, attemptToFixRetries: UInt = 0) {
            self.enabled = enabled; self.attemptToFixRetries = attemptToFixRetries
        }
    }

    /// Module → Suite → [TestName]. Used for Known Tests response.
    public typealias KnownTestsMap = [String: [String: [String]]]

    /// A single test to be skipped in ITR response.
    public struct SkippableTest: Sendable {
        public let name: String
        public let suite: String

        public init(name: String, suite: String) { self.name = name; self.suite = suite }
    }

    /// Module → Suite → TestName → Properties. Used for Test Management response.
    public typealias TestManagementMap = [String: [String: [String: MockTestProperties]]]

    public struct MockTestProperties: Sendable {
        public var disabled: Bool
        public var quarantined: Bool
        public var attemptToFix: Bool

        public init(disabled: Bool = false, quarantined: Bool = false, attemptToFix: Bool = false) {
            self.disabled = disabled; self.quarantined = quarantined; self.attemptToFix = attemptToFix
        }
    }
}

// MARK: - Private: ZLIB Decompression (mirrors DataCompression.swift's deflate encoding)

private extension Data {
    var _zlibInflated: Data? {
        guard !isEmpty else { return self }
        return withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Data? in
            guard let src = ptr.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var destCapacity = Swift.max(count * 4, 1024)
            while destCapacity <= count * 64 {
                var dest = [UInt8](repeating: 0, count: destCapacity)
                let decoded = compression_decode_buffer(&dest, destCapacity, src, count, nil, COMPRESSION_ZLIB)
                if decoded > 0 { return Data(bytes: dest, count: decoded) }
                destCapacity *= 2
            }
            return nil
        }
    }
}

// MARK: - Private: Dynamic CodingKey for MockLog

private struct _DynamicKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
