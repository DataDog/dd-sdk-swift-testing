/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2025-Present Datadog, Inc.
 */

import Compression
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - Decoded Span Types

/// Top-level envelope sent to /api/v2/citestcycle.
public struct MockSpanEnvelope: Decodable {
    public let version: Int
    public let metadata: [String: [String: String]]
    public let events: [MockSpanEvent]
    
    var extended: [MockSpanEvent] { events.map { $0.extend(metadata: metadata) } }
    
    /// All span payloads from all events.
    public var allSpans: [MockSpan] { extended.compactMap(\.span) }
    /// Only events with type == "span"
    public var infoSpans: [MockSpan] { extended.filter { $0.isSpan }.compactMap(\.span) }
    /// Only events with type == "test".
    public var testSpans: [MockSpan] { extended.filter { $0.isTest }.compactMap(\.span) }
    /// Only end events
    public var testEvents: [MockTestEventSpan] { extended.filter { $0.isEvent }.compactMap(\.event) }
}

public enum MockSpanEvent: Decodable {
    case span(MockSpan)
    case test(MockSpan)
    case suiteEnd(MockTestEventSpan)
    case moduleEnd(MockTestEventSpan)
    case sessionEnd(MockTestEventSpan)
    
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
    
    var span: MockSpan? {
        switch self {
        case .span(let span), .test(let span): return span
        default: return nil
        }
    }
    
    var event: MockTestEventSpan? {
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
            let envelope = try container.decode(Wrapper<MockSpan>.self)
            guard envelope.version == 1 else {
                throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                        debugDescription: "Unsupported version: \(envelope.version)"))
            }
            self = .span(envelope.content)
        case .test:
            let envelope = try container.decode(Wrapper<MockSpan>.self)
            guard envelope.version == 2 else {
                throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                        debugDescription: "Unsupported version: \(envelope.version)"))
            }
            self = .test(envelope.content)
        case .suiteEnd:
            let envelope = try container.decode(Wrapper<MockTestEventSpan>.self)
            guard envelope.version == 1 else {
                throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                        debugDescription: "Unsupported version: \(envelope.version)"))
            }
            self = .suiteEnd(envelope.content)
        case .moduleEnd:
            let envelope = try container.decode(Wrapper<MockTestEventSpan>.self)
            guard envelope.version == 1 else {
                throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                        debugDescription: "Unsupported version: \(envelope.version)"))
            }
            self = .moduleEnd(envelope.content)
        case .sessionEnd:
            let envelope = try container.decode(Wrapper<MockTestEventSpan>.self)
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

public struct MockSpan: Decodable {
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

public struct MockTestEventSpan: Decodable {
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

// MARK: - Decoded Coverage Types

/// Top-level payload received at /api/v2/citestcov (extracted from the "coverage" multipart field).
public struct MockCoveragePayload: Decodable {
    public let version: Int
    public let coverages: [MockTestCoverage]
}

/// Per-test coverage entry within a payload.
public struct MockTestCoverage: Decodable {
    public let testSessionId: UInt64
    public let testSuiteId: UInt64
    public let spanId: UInt64
    public let files: [MockCoverageFile]

    enum CodingKeys: String, CodingKey {
        case testSessionId = "test_session_id"
        case testSuiteId = "test_suite_id"
        case spanId = "span_id"
        case files
    }
}

/// A covered-file entry. `bitmap` is a bit-per-line coverage mask, base64-decoded from JSON.
public struct MockCoverageFile: Decodable {
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

// MARK: - Decoded Log Types

/// A single log entry received at /api/v2/logs.
public struct MockLog: Decodable {
    public let fields: [String: MockJSONValue]

    public subscript(key: String) -> MockJSONValue? { fields[key] }

    public var message: String? { fields["message"]?.stringValue }
    public var status: String? { fields["status"]?.stringValue }
    public var service: String? { fields["service"]?.stringValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _DynamicKey.self)
        var fields: [String: MockJSONValue] = [:]
        for key in container.allKeys {
            fields[key.stringValue] = (try? container.decode(MockJSONValue.self, forKey: key)) ?? .null
        }
        self.fields = fields
    }
}

/// A flexible JSON value used in log fields.
public enum MockJSONValue: Decodable, CustomStringConvertible {
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

// MARK: - Mock Configuration Types

/// Configure the settings response returned to the SDK.
public struct MockSettings {
    public var itrEnabled: Bool
    public var codeCoverage: Bool
    public var testsSkipping: Bool
    public var knownTestsEnabled: Bool
    public var requireGit: Bool
    public var flakyTestRetriesEnabled: Bool
    public var earlyFlakeDetection: MockEFDConfig
    public var testManagement: MockTestManagementConfig

    public init(
        itrEnabled: Bool = false, codeCoverage: Bool = false, testsSkipping: Bool = false,
        knownTestsEnabled: Bool = false, requireGit: Bool = false, flakyTestRetriesEnabled: Bool = false,
        earlyFlakeDetection: MockEFDConfig = .init(), testManagement: MockTestManagementConfig = .init()
    ) {
        self.itrEnabled = itrEnabled; self.codeCoverage = codeCoverage
        self.testsSkipping = testsSkipping; self.knownTestsEnabled = knownTestsEnabled
        self.requireGit = requireGit; self.flakyTestRetriesEnabled = flakyTestRetriesEnabled
        self.earlyFlakeDetection = earlyFlakeDetection; self.testManagement = testManagement
    }
}

/// Early Flake Detection configuration returned in settings.
public struct MockEFDConfig {
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
public struct MockTestManagementConfig {
    public var enabled: Bool
    public var attemptToFixRetries: UInt

    public init(enabled: Bool = false, attemptToFixRetries: UInt = 0) {
        self.enabled = enabled; self.attemptToFixRetries = attemptToFixRetries
    }
}

/// Module → Suite → [TestName]. Used for Known Tests response.
public typealias MockKnownTestsMap = [String: [String: [String]]]

/// A single test to be skipped in ITR response.
public struct MockSkippableTest {
    public let name: String
    public let suite: String

    public init(name: String, suite: String) { self.name = name; self.suite = suite }
}

/// Module → Suite → TestName → Properties. Used for Test Management response.
public typealias MockTestManagementMap = [String: [String: [String: MockTestProperties]]]

public struct MockTestProperties {
    public var disabled: Bool
    public var quarantined: Bool
    public var attemptToFix: Bool

    public init(disabled: Bool = false, quarantined: Bool = false, attemptToFix: Bool = false) {
        self.disabled = disabled; self.quarantined = quarantined; self.attemptToFix = attemptToFix
    }
}

// MARK: - Error Types

public enum MockBackendError: Error {
    case socketCreationFailed, bindFailed, listenFailed
}

// MARK: - DDMockBackend

/// A mock HTTP backend that handles all Datadog SDK exporter endpoints.
/// Stores received payloads and returns configurable responses so integration
/// tests can verify SDK behaviour end-to-end without hitting real Datadog servers.
///
/// Usage:
/// ```swift
/// let backend = DDMockBackend()
/// try backend.start()
/// // Configure endpoint in your SDK: .other(testsBaseURL: backend.baseURL, logsBaseURL: backend.baseURL)
/// // ... run tests ...
/// backend.waitForSpans()
/// let spans = backend.allSpans
/// backend.stop()
/// ```
public final class DDMockBackend {

    // MARK: - Configurable Responses

    /// Returned for POST /api/v2/libraries/tests/services/setting
    public var settings: MockSettings = .init()
    /// Returned for POST /api/v2/ci/libraries/tests
    public var knownTests: MockKnownTestsMap = [:]
    /// Returned for POST /api/v2/ci/tests/skippable
    public var skippableTests: [MockSkippableTest] = []
    /// Correlation ID included in the skippable tests response.
    public var skippableTestsCorrelationId: String = "mock-correlation-id"
    /// Returned for GET /api/v2/test/libraries/test-management/tests
    public var testManagement: MockTestManagementMap = [:]

    // MARK: - Received Data (thread-safe read via computed properties)

    private let _lock = DispatchQueue(label: "DDMockBackend.lock", qos: .userInteractive,
                                      target: .global(qos: .userInteractive))
    private var _spanEnvelopes: [MockSpanEnvelope] = []
    private var _logs: [[MockLog]] = []
    private var _coveragePayloads: [MockCoveragePayload] = []
    private var _settingsRequests: [Data] = []
    private var _knownTestsRequests: [Data] = []
    private var _skippableTestsRequests: [Data] = []
    private var _testManagementRequests: [Data] = []
    private var _searchCommitsRequests: [Data] = []
    private var _packfileRequests: [Data] = []

    /// All decoded span envelopes received so far.
    public var spanEnvelopes: [MockSpanEnvelope] { _lock.sync { _spanEnvelopes } }
    /// All spans across all received envelopes.
    public var allSpans: [MockSpan] { _lock.sync { _spanEnvelopes.flatMap(\.allSpans) } }
    /// All spans across all received envelopes.
    public var allInfoSpans: [MockSpan] { _lock.sync { _spanEnvelopes.flatMap(\.infoSpans) } }
    /// All test-type spans across all received envelopes.
    public var allTestSpans: [MockSpan] { _lock.sync { _spanEnvelopes.flatMap(\.testSpans) } }
    /// All log batches received so far.
    public var logs: [[MockLog]] { _lock.sync { _logs } }
    /// All individual log entries across all batches.
    public var allLogs: [MockLog] { _lock.sync { _logs.flatMap { $0 } } }
    /// All decoded coverage payloads received so far.
    public var coveragePayloads: [MockCoveragePayload] { _lock.sync { _coveragePayloads } }
    /// All individual coverage entries across all payloads.
    public var allCoverages: [MockTestCoverage] { _lock.sync { _coveragePayloads.flatMap(\.coverages) } }
    /// Raw bodies of all settings requests made by the SDK.
    public var settingsRequests: [Data] { _lock.sync { _settingsRequests } }
    /// Raw bodies of all known-tests requests.
    public var knownTestsRequests: [Data] { _lock.sync { _knownTestsRequests } }
    /// Raw bodies of all skippable-tests requests.
    public var skippableTestsRequests: [Data] { _lock.sync { _skippableTestsRequests } }
    /// Raw bodies of all test-management requests.
    public var testManagementRequests: [Data] { _lock.sync { _testManagementRequests } }
    /// Raw bodies of all git search-commits requests.
    public var searchCommitsRequests: [Data] { _lock.sync { _searchCommitsRequests } }

    // MARK: - Server

    private var _serverSocket: Int32 = -1
    public private(set) var serverPort: Int = 0
    private var _isRunning = false
    private var _serverQueue: DispatchQueue?

    /// Base URL for this backend, e.g. `http://127.0.0.1:12345`.
    /// Pass this to `Endpoint.other(testsBaseURL:logsBaseURL:)` when configuring the SDK.
    public var baseURL: URL { URL(string: "http://127.0.0.1:\(serverPort)")! }

    public init() {}
    deinit { stop() }

    // MARK: - Lifecycle

    public func start() throws {
        #if canImport(Darwin)
        _serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        #else
        _serverSocket = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard _serverSocket >= 0 else { throw MockBackendError.socketCreationFailed }

        var yes: Int32 = 1
        setsockopt(_serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        let flags = fcntl(_serverSocket, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(_serverSocket, F_SETFL, flags | O_NONBLOCK) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_ANY
        let bindResult = withUnsafePointer(to: &addr) {
            bind(_serverSocket, UnsafeRawPointer($0).assumingMemoryBound(to: sockaddr.self),
                 socklen_t(MemoryLayout<sockaddr_in>.size))
        }
        guard bindResult >= 0 else { close(_serverSocket); throw MockBackendError.bindFailed }

        var actualAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actualAddr) {
            _ = getsockname(_serverSocket, UnsafeMutableRawPointer($0).assumingMemoryBound(to: sockaddr.self), &addrLen)
        }
        #if canImport(Darwin)
        serverPort = Int(CFSwapInt16BigToHost(actualAddr.sin_port))
        #else
        serverPort = Int(ntohs(actualAddr.sin_port))
        #endif

        guard listen(_serverSocket, 10) >= 0 else { close(_serverSocket); throw MockBackendError.listenFailed }

        _isRunning = true
        _serverQueue = DispatchQueue(label: "DDMockBackend", qos: .userInteractive, attributes: .concurrent)
        _serverQueue?.async { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        _isRunning = false
        if _serverSocket >= 0 {
            #if canImport(Darwin)
            Darwin.shutdown(_serverSocket, SHUT_RDWR)
            #elseif canImport(Glibc)
            Glibc.shutdown(_serverSocket, Int32(SHUT_RDWR))
            #elseif canImport(Musl)
            Musl.shutdown(_serverSocket, Int32(SHUT_RDWR))
            #endif
            close(_serverSocket)
            _serverSocket = -1
        }
        _serverQueue?.sync(flags: .barrier) {}
        _serverQueue = nil
    }

    /// Clears all received data without affecting configuration.
    public func reset() {
        _lock.sync {
            _spanEnvelopes.removeAll(); _logs.removeAll()
            _coveragePayloads.removeAll(); _settingsRequests.removeAll()
            _knownTestsRequests.removeAll(); _skippableTestsRequests.removeAll()
            _testManagementRequests.removeAll(); _searchCommitsRequests.removeAll()
            _packfileRequests.removeAll()
        }
    }

    // MARK: - Wait Helpers

    /// Blocks until at least `count` span envelopes have been received, or `timeout` elapses.
    @discardableResult
    public func waitForSpans(count: Int = 1, timeout: TimeInterval = 10) -> Bool {
        poll(timeout: timeout) { self._lock.sync { self._spanEnvelopes.count >= count } }
    }

    /// Blocks until at least `count` log batches have been received, or `timeout` elapses.
    @discardableResult
    public func waitForLogs(count: Int = 1, timeout: TimeInterval = 10) -> Bool {
        poll(timeout: timeout) { self._lock.sync { self._logs.count >= count } }
    }

    /// Blocks until at least `count` coverage payloads have been received, or `timeout` elapses.
    @discardableResult
    public func waitForCoverage(count: Int = 1, timeout: TimeInterval = 10) -> Bool {
        poll(timeout: timeout) { self._lock.sync { self._coveragePayloads.count >= count } }
    }

    /// Blocks until at least `count` settings requests have been received, or `timeout` elapses.
    @discardableResult
    public func waitForSettings(count: Int = 1, timeout: TimeInterval = 10) -> Bool {
        poll(timeout: timeout) { self._lock.sync { self._settingsRequests.count >= count } }
    }

    private func poll(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition()
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while _isRunning {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                accept(_serverSocket, UnsafeMutableRawPointer($0).assumingMemoryBound(to: sockaddr.self), &clientAddrLen)
            }
            if clientSocket < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { Thread.sleep(forTimeInterval: 0.01); continue }
                if !_isRunning { break }
                continue
            }
            _serverQueue?.async { [self] in
                handleClient(socket: clientSocket)
                close(clientSocket)
            }
        }
    }

    private func handleClient(socket: Int32) {
        guard let request = readRequest(socket: socket) else {
            sendStatus(socket: socket, status: "400 Bad Request", body: Data("{}".utf8))
            return
        }
        route(request: request, socket: socket)
    }

    // MARK: - Routing

    private func route(request: _RawRequest, socket: Int32) {
        let body = request.decompressedBody
        print("BODY: \(String(data: body, encoding: .utf8)!)")

        switch request.path {
        case "/api/v2/citestcycle":
            if let envelope = try? JSONDecoder().decode(MockSpanEnvelope.self, from: body) {
                _lock.sync { _spanEnvelopes.append(envelope) }
            }
            sendStatus(socket: socket, status: "200 OK", body: Data("{}".utf8))

        case "/api/v2/logs":
            if let logs = try? JSONDecoder().decode([MockLog].self, from: body) {
                _lock.sync { _logs.append(logs) }
            }
            sendStatus(socket: socket, status: "200 OK", body: Data("{}".utf8))

        case "/api/v2/citestcov":
            if let payload = parseCoveragePayload(request) {
                _lock.sync { _coveragePayloads.append(payload) }
            }
            sendStatus(socket: socket, status: "200 OK", body: Data("{}".utf8))

        case "/api/v2/libraries/tests/services/setting":
            _lock.sync { _settingsRequests.append(body) }
            sendJSON(socket: socket, data: buildSettingsResponse())

        case "/api/v2/ci/libraries/tests":
            _lock.sync { _knownTestsRequests.append(body) }
            sendJSON(socket: socket, data: buildKnownTestsResponse())

        case "/api/v2/ci/tests/skippable":
            _lock.sync { _skippableTestsRequests.append(body) }
            sendJSON(socket: socket, data: buildSkippableTestsResponse())

        case "/api/v2/git/repository/search_commits":
            _lock.sync { _searchCommitsRequests.append(body) }
            sendJSON(socket: socket, data: Data("{\"data\":[]}".utf8))

        case "/api/v2/git/repository/packfile":
            _lock.sync { _packfileRequests.append(body) }
            sendStatus(socket: socket, status: "200 OK", body: Data("{}".utf8))

        case "/api/v2/test/libraries/test-management/tests":
            _lock.sync { _testManagementRequests.append(body) }
            sendJSON(socket: socket, data: buildTestManagementResponse())

        default:
            sendStatus(socket: socket, status: "404 Not Found", body: Data("{}".utf8))
        }
    }

    // MARK: - Response Builders

    private func buildSettingsResponse() -> Data {
        let s = settings
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
        let dataArray: [[String: Any]] = skippableTests.enumerated().map { idx, test in
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
            "meta": ["correlation_id": skippableTestsCorrelationId],
            "data": dataArray
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private func buildTestManagementResponse() -> Data {
        var modulesDict: [String: Any] = [:]
        for (moduleName, suites) in testManagement {
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
    private func parseCoveragePayload(_ request: _RawRequest) -> MockCoveragePayload? {
        guard let contentType = request.headers["content-type"],
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

        guard let json = extractMultipartField(named: "coverage", from: request.rawBody, boundary: boundary)
        else { return nil }

        return try? JSONDecoder().decode(MockCoveragePayload.self, from: json)
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

    // MARK: - HTTP I/O

    private func readRequest(socket: Int32) -> _RawRequest? {
        var totalData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        // Read until we have complete headers
        while true {
            let n = recv(socket, &buffer, buffer.count, 0)
            if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { Thread.sleep(forTimeInterval: 0.01); continue }
                break
            }
            if n == 0 { break }
            totalData.append(contentsOf: buffer[0..<n])
            if totalData.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) != nil { break }
        }

        guard let headerEndRange = totalData.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else { return nil }

        let headerData = totalData.subdata(in: 0..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        // Strip query string from path
        let path = parts[1].components(separatedBy: "?").first ?? parts[1]

        var headers: [String: String] = [:]
        var contentLength = 0
        for line in lines.dropFirst() {
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { break }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
            if key == "content-length" { contentLength = Int(value) ?? 0 }
        }

        // Collect body bytes already read past the header
        var body = totalData.subdata(in: headerEndRange.upperBound..<totalData.count)

        // Read remaining body bytes
        let remaining = contentLength - body.count
        if remaining > 0 {
            var bodyBuffer = [UInt8](repeating: 0, count: remaining)
            var totalRead = 0
            while totalRead < remaining {
                let n = recv(socket, &bodyBuffer[totalRead], remaining - totalRead, 0)
                if n < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { Thread.sleep(forTimeInterval: 0.01); continue }
                    break
                }
                if n == 0 { break }
                totalRead += n
            }
            body.append(contentsOf: bodyBuffer[0..<totalRead])
        }

        return _RawRequest(path: path, headers: headers, rawBody: body)
    }

    private func sendJSON(socket: Int32, data: Data) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        _ = header.withCString { send(socket, $0, strlen($0), 0) }
        _ = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress, !data.isEmpty else { return 0 }
            return send(socket, base, data.count, 0)
        }
    }

    private func sendStatus(socket: Int32, status: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        _ = header.withCString { send(socket, $0, strlen($0), 0) }
        _ = body.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress, !body.isEmpty else { return 0 }
            return send(socket, base, body.count, 0)
        }
    }
}

// MARK: - Private: Raw Request

private struct _RawRequest {
    let path: String
    let headers: [String: String]
    let rawBody: Data

    var decompressedBody: Data {
        guard headers["content-encoding"]?.lowercased() == "deflate" else { return rawBody }
        return rawBody._zlibInflated ?? rawBody
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
