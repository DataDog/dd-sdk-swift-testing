/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
@testable import EventsExporter
import XCTest
import TestUtils

private struct DummyError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

// MARK: - LibraryConfigurationCommunicationError.description

final class LibraryConfigurationCommunicationErrorTests: XCTestCase {
    func testDescription_unauthorized_mentionsApiKey() {
        let error = makeError(reason: .unauthorized)
        let text = error.description

        XCTAssertTrue(text.contains("Req"), "description should include the request name")
        XCTAssertTrue(text.contains("DD_API_KEY"),
                      "unauthorized description should ask the user to verify DD_API_KEY")
        XCTAssertTrue(text.contains("Payload: {\"k\":1}"),
                      "description should include the payload")
    }

    func testDescription_communicationFailed_includesUnderlyingError() {
        let underlying = DummyError(message: "transport boom")
        let error = makeError(reason: .communicationFailed(underlying))

        let text = error.description
        XCTAssertTrue(text.contains("no response from backend"))
        XCTAssertTrue(text.contains("transport boom"))
        XCTAssertTrue(text.contains("Payload: {\"k\":1}"))
    }

    func testDescription_responseDecodingFailed_includesBodyAndUnderlyingError() {
        let underlying = DummyError(message: "decode boom")
        let body = Data("<html>nope</html>".utf8)
        let error = makeError(reason: .responseDecodingFailed(body: body, error: underlying))

        let text = error.description
        XCTAssertTrue(text.contains("invalid response body"))
        XCTAssertTrue(text.contains("decode boom"))
        XCTAssertTrue(text.contains("Response: <html>nope</html>"))
        XCTAssertTrue(text.contains("Payload: {\"k\":1}"))
    }

    func testDescription_payloadEncodingFailed_includesPayload() {
        let error = makeError(reason: .payloadEncodingFailed)
        let text = error.description
        XCTAssertTrue(text.contains("payload could not be encoded"))
        XCTAssertTrue(text.contains("Payload: {\"k\":1}"))
    }

    private func makeError(reason: LibraryConfigurationCommunicationError.Reason)
        -> LibraryConfigurationCommunicationError
    {
        LibraryConfigurationCommunicationError(requestName: "Req", payload: "{\"k\":1}", reason: reason)
    }
}

// MARK: - Service throw paths

final class LibraryConfigurationServiceThrowTests: XCTestCase {
    private var server: HttpTestServer!

    override func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    private func makeApi(baseURL: URL) -> TestOptimizationApiService {
        TestOptimizationApiService(serviceName: "service",
                                   environment: "environment",
                                   applicationName: "app",
                                   version: "1.0",
                                   hostname: nil,
                                   apiKey: "apikey",
                                   endpoint: .other(testsBaseURL: baseURL, logsBaseURL: baseURL),
                                   clientId: "client",
                                   payloadCompression: false,
                                   logger: Log.instance)
    }

    /// Drive an async API call from the sync test, mapping `APICallError` to
    /// the configuration-error type the same way the production factories do.
    private func invokeConfigurationApi<V>(
        requestName: String, payload: String,
        _ call: @Sendable @escaping () async throws(APICallError) -> V
    ) throws(LibraryConfigurationCommunicationError) -> V {
        do {
            return try waitForAsync { () async throws(APICallError) -> V in
                try await call()
            }
        } catch let error {
            throw LibraryConfigurationCommunicationError(requestName: requestName,
                                                         payload: payload, error: error)
        }
    }

    // MARK: - SettingsService

    func testSettingsService_throwsUnauthorizedOn401() throws {
        let baseURL = try startServer(replyingWith: status(401, reason: "Unauthorized"))
        let api = makeApi(baseURL: baseURL).settings

        let error = expectError {
            _ = try invokeConfigurationApi(requestName: "SettingsRequest",
                                           payload: "") { () async throws(APICallError) -> TracerSettings in
                try await api.tracerSettings(service: "service", env: "env",
                                             repositoryURL: "repo", branch: "main", sha: "abc",
                                             testLevel: ITRTestLevel.test,
                                             configurations: [:], customConfigurations: [:])
            }
        }
        XCTAssertEqual(error?.requestName, "SettingsRequest")
        if case .unauthorized = error?.reason {} else {
            XCTFail("Expected .unauthorized, got \(error?.reason as Any)")
        }
    }

    func testSettingsService_throwsCommunicationFailedOn500() throws {
        let baseURL = try startServer(replyingWith: status(500, reason: "Internal Server Error"))
        let api = makeApi(baseURL: baseURL).settings

        let error = expectError {
            _ = try invokeConfigurationApi(requestName: "SettingsRequest",
                                           payload: "") { () async throws(APICallError) -> TracerSettings in
                try await api.tracerSettings(service: "service", env: "env",
                                             repositoryURL: "repo", branch: "main", sha: "abc",
                                             testLevel: ITRTestLevel.test,
                                             configurations: [:], customConfigurations: [:])
            }
        }
        XCTAssertEqual(error?.requestName, "SettingsRequest")
        guard case .communicationFailed(let underlying)? = error?.reason else {
            XCTFail("Expected .communicationFailed, got \(error?.reason as Any)")
            return
        }
        XCTAssertTrue("\(underlying)".contains("500"),
                      "communicationFailed should carry the underlying HTTP error")
    }

    func testSettingsService_throwsResponseDecodingFailedOnGarbageBody() throws {
        let body = Data("<not-json>".utf8)
        let baseURL = try startServer(replyingWith: status(200, reason: "OK"), body: body)
        let api = makeApi(baseURL: baseURL).settings

        let error = expectError {
            _ = try invokeConfigurationApi(requestName: "SettingsRequest",
                                           payload: "") { () async throws(APICallError) -> TracerSettings in
                try await api.tracerSettings(service: "service", env: "env",
                                             repositoryURL: "repo", branch: "main", sha: "abc",
                                             testLevel: ITRTestLevel.test,
                                             configurations: [:], customConfigurations: [:])
            }
        }
        XCTAssertEqual(error?.requestName, "SettingsRequest")
        guard case .responseDecodingFailed(let receivedBody, _)? = error?.reason else {
            XCTFail("Expected .responseDecodingFailed, got \(error?.reason as Any)")
            return
        }
        XCTAssertEqual(receivedBody, body)
    }

    func testSettingsService_succeedsOnValidResponse() throws {
        let baseURL = try startServerEchoingRequestId { id in Self.validSettingsBody(id: id) }
        let api = makeApi(baseURL: baseURL).settings

        let settings = try invokeConfigurationApi(requestName: "SettingsRequest",
                                                  payload: "") { () async throws(APICallError) -> TracerSettings in
            try await api.tracerSettings(service: "service", env: "env",
                                         repositoryURL: "repo", branch: "main", sha: "abc",
                                         testLevel: ITRTestLevel.test,
                                         configurations: [:], customConfigurations: [:])
        }
        XCTAssertTrue(settings.flakyTestRetriesEnabled)
        XCTAssertTrue(settings.knownTestsEnabled)
        XCTAssertTrue(settings.itr.itrEnabled)
    }

    // MARK: - Other services (one throw scenario each)

    func testSkippableTestsService_throwsUnauthorizedOn403() throws {
        let baseURL = try startServer(replyingWith: status(403, reason: "Forbidden"))
        let api = makeApi(baseURL: baseURL).tia

        let error = expectError {
            _ = try invokeConfigurationApi(requestName: "SkipTestsRequest",
                                           payload: "") { () async throws(APICallError) -> SkipTests in
                try await api.skippableTests(repositoryURL: "repo", sha: "abc",
                                             environment: "env", service: "service",
                                             testLevel: ITRTestLevel.test,
                                             configurations: [:], customConfigurations: [:])
            }
        }
        XCTAssertEqual(error?.requestName, "SkipTestsRequest")
        if case .unauthorized = error?.reason {} else {
            XCTFail("Expected .unauthorized, got \(error?.reason as Any)")
        }
    }

    func testKnownTestsService_throwsCommunicationFailedOn500() throws {
        let baseURL = try startServer(replyingWith: status(500, reason: "Internal Server Error"))
        let api = makeApi(baseURL: baseURL).knownTests

        let error = expectError {
            _ = try invokeConfigurationApi(requestName: "Known Tests Request",
                                           payload: "") { () async throws(APICallError) -> KnownTestsResult in
                try await api.tests(service: "service", env: "env", repositoryURL: "repo",
                                    configurations: [:], customConfigurations: [:])
            }
        }
        XCTAssertEqual(error?.requestName, "Known Tests Request")
        if case .communicationFailed = error?.reason {} else {
            XCTFail("Expected .communicationFailed, got \(error?.reason as Any)")
        }
    }

    func testTestManagementService_throwsResponseDecodingFailedOnBadBody() throws {
        let body = Data("not-json".utf8)
        let baseURL = try startServer(replyingWith: status(200, reason: "OK"), body: body)
        let api = makeApi(baseURL: baseURL).testManagement

        let error = expectError {
            _ = try invokeConfigurationApi(requestName: "Test Management Tests Request",
                                           payload: "") { () async throws(APICallError) -> TestManagementTestsInfo in
                try await api.tests(repositoryURL: "repo",
                                    sha: String?.none,
                                    commitMessage: String?.none,
                                    branch: String?.none,
                                    module: String?.none)
            }
        }
        XCTAssertEqual(error?.requestName, "Test Management Tests Request")
        guard case .responseDecodingFailed(let receivedBody, _)? = error?.reason else {
            XCTFail("Expected .responseDecodingFailed, got \(error?.reason as Any)")
            return
        }
        XCTAssertEqual(receivedBody, body)
    }

    func testSearchExistingCommits_throwsUnauthorizedOn401() throws {
        let baseURL = try startServer(replyingWith: status(401, reason: "Unauthorized"))
        let api = makeApi(baseURL: baseURL).git

        let error = expectError {
            _ = try invokeConfigurationApi(requestName: "SearchCommitsRequest",
                                           payload: "") { () async throws(APICallError) -> [String] in
                try await api.searchCommits(repositoryURL: "repo", commits: ["abc"])
            }
        }
        XCTAssertEqual(error?.requestName, "SearchCommitsRequest")
        if case .unauthorized = error?.reason {} else {
            XCTFail("Expected .unauthorized, got \(error?.reason as Any)")
        }
    }

    // MARK: - helpers

    private func startServer(replyingWith status: HTTPTestResponseSender.Status,
                             body: Data = Data("{}".utf8)) throws -> URL
    {
        let captured = (status, body)
        server = HttpTestServer { _, response in
            response.sendResponse(status: captured.0,
                                  contentType: "application/json",
                                  body: captured.1)
        }
        try server.start()
        return server.baseURL
    }

    /// Start a test server that echoes the request's `data.id` back into the
    /// response body — matching the real Datadog backend, which reflects the
    /// client-supplied UUID so callers can correlate request/response.
    private func startServerEchoingRequestId(
        body: @escaping @Sendable (_ requestId: String) -> Data
    ) throws -> URL {
        server = HttpTestServer { request, response in
            let requestId = (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any])
                .flatMap { $0["data"] as? [String: Any] }
                .flatMap { $0["id"] as? String } ?? "missing-id"
            response.sendResponse(status: HTTPTestResponseSender.Status(code: 200, reason: "OK"),
                                  contentType: "application/json",
                                  body: body(requestId))
        }
        try server.start()
        return server.baseURL
    }

    private func status(_ code: UInt16, reason: String) -> HTTPTestResponseSender.Status {
        HTTPTestResponseSender.Status(code: code, reason: reason)
    }

    private func expectError(_ block: () throws -> Void,
                             file: StaticString = #file, line: UInt = #line)
        -> LibraryConfigurationCommunicationError?
    {
        do {
            try block()
            XCTFail("Expected throw", file: file, line: line)
            return nil
        } catch let error as LibraryConfigurationCommunicationError {
            return error
        } catch {
            XCTFail("Expected LibraryConfigurationCommunicationError, got \(type(of: error))",
                    file: file, line: line)
            return nil
        }
    }

    private static func validSettingsBody(id: String = "1") -> Data {
        let payload: [String: Any] = [
            "data": [
                "id": id,
                "type": "ci_app_tracers_test_service_settings",
                "attributes": [
                    "itr_enabled": true,
                    "code_coverage": false,
                    "tests_skipping": false,
                    "known_tests_enabled": true,
                    "require_git": false,
                    "flaky_test_retries_enabled": true,
                    "early_flake_detection": [
                        "enabled": false,
                        "slow_test_retries": [String: Int](),
                        "faulty_session_threshold": 0
                    ] as [String: Any],
                    "test_management": [
                        "enabled": false,
                        "attempt_to_fix_retries": 0
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}
