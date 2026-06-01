/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import Foundation

/// True when the test bundle is running on watchOS. Used to skip suites that drive
/// uploads through `URLProtocol`-based mocks (`ServerMock`): watchOS' URLSession
/// honors `URLSessionConfiguration.protocolClasses` only for asynchronous, run-loop-
/// driven calls (`XCTestExpectation` + `waitForExpectations`), and silently bypasses
/// the protocol when the caller is using a custom run-loop pump — even though
/// `URLProtocol.canInit` is invoked and returns `true`. The result is that uploads
/// hit the real network and the mocks never fire.
#if os(watchOS)
let isWatchOS = true
#else
let isWatchOS = false
#endif

// MARK: - PerformancePreset Mocks

struct StoragePerformanceMock: StoragePerformancePreset {
    let maxFileSize: UInt64
    let maxDirectorySize: UInt64
    let maxFileAgeForWrite: TimeInterval
    let minFileAgeForRead: TimeInterval
    let maxFileAgeForRead: TimeInterval
    let maxObjectsInFile: Int
    let maxObjectSize: UInt64
    let synchronousWrite: Bool

    static let readAllFiles = StoragePerformanceMock(
        maxFileSize: .max,
        maxDirectorySize: .max,
        maxFileAgeForWrite: 0,
        minFileAgeForRead: -1, // make all files eligible for read
        maxFileAgeForRead: .distantFuture, // make all files eligible for read
        maxObjectsInFile: .max,
        maxObjectSize: .max,
        synchronousWrite: true
    )

    static let writeEachObjectToNewFileAndReadAllFiles = StoragePerformanceMock(
        maxFileSize: .max,
        maxDirectorySize: .max,
        maxFileAgeForWrite: 0, // always return new file for writting
        minFileAgeForRead: readAllFiles.minFileAgeForRead,
        maxFileAgeForRead: readAllFiles.maxFileAgeForRead,
        maxObjectsInFile: 1, // write each data to new file
        maxObjectSize: .max,
        synchronousWrite: true
    )

    /// All writes accumulate in the same file until it is explicitly closed via
    /// `flush()`. Use this to test that the uploader correctly assembles a
    /// `message-batch` from several entries that share one on-disk batch.
    static let appendToOneFile = StoragePerformanceMock(
        maxFileSize: .max,
        maxDirectorySize: .max,
        maxFileAgeForWrite: .greatestFiniteMagnitude,
        minFileAgeForRead: readAllFiles.minFileAgeForRead,
        maxFileAgeForRead: readAllFiles.maxFileAgeForRead,
        maxObjectsInFile: .max,
        maxObjectSize: .max,
        synchronousWrite: true
    )
}

struct UploadPerformanceMock: UploadPerformancePreset {
    let initialUploadDelay: TimeInterval
    let defaultUploadDelay: TimeInterval
    let minUploadDelay: TimeInterval
    let maxUploadDelay: TimeInterval
    let uploadDelayChangeRate: Double
    let uploadQueuePriority: DispatchQoS

    static let veryQuick = UploadPerformanceMock(
        initialUploadDelay: 0.05,
        defaultUploadDelay: 0.05,
        minUploadDelay: 0.05,
        maxUploadDelay: 0.05,
        uploadDelayChangeRate: 0,
        uploadQueuePriority: .userInteractive
    )
}

extension PerformancePreset {
    static let readAllFiles = Self(any: StoragePerformanceMock.readAllFiles,
                                   upload: UploadPerformanceMock.veryQuick)
    static let writeEachObjectToNewFileAndReadAllFiles = Self(any: StoragePerformanceMock.writeEachObjectToNewFileAndReadAllFiles,
                                                              upload: UploadPerformanceMock.veryQuick)
    static let appendToOneFile = Self(any: StoragePerformanceMock.appendToOneFile,
                                      upload: UploadPerformanceMock.veryQuick)
}

extension DataFormat {
    static func mockAny() -> DataFormat {
        return mockWith()
    }

    static func mockWith(
        prefix: String = .mockAny(),
        suffix: String = .mockAny(),
        separator: String = .mockAny()
    ) -> DataFormat {
        return DataFormat(
            prefix: Data(prefix.utf8),
            suffix: Data(suffix.utf8),
            separator: Data(separator.utf8)
        )
    }

    /// Build the on-disk representation of a sequence of pre-encoded entries
    /// exactly as `FileWriter` would lay them out: `prefix + entries[0] +
    /// separator + entries[1] + ...` (no suffix — the reader appends that).
    /// Useful for seeding a file before exercising `FileReader` directly.
    func formatFileContents(_ entries: [Data]) -> Data {
        guard let first = entries.first else { return Data() }
        return entries.dropFirst().reduce(into: prefix + first) { $0 += separator + $1 }
    }
}

/// `DateProvider` mock returning consecutive dates in custom intervals, starting from given reference date.
class RelativeDateProvider: DateProvider {
    private(set) var date: Date
    internal let timeInterval: TimeInterval
    private let queue = DispatchQueue(label: "queue-RelativeDateProvider-\(UUID().uuidString)")

    private init(date: Date, timeInterval: TimeInterval) {
        self.date = date
        self.timeInterval = timeInterval
    }

    convenience init(using date: Date = Date()) {
        self.init(date: date, timeInterval: 0)
    }

    convenience init(startingFrom referenceDate: Date = Date(), advancingBySeconds timeInterval: TimeInterval = 0) {
        self.init(date: referenceDate, timeInterval: timeInterval)
    }

    /// Returns current date and advances next date by `timeInterval`.
    func currentDate() -> Date {
        defer {
            queue.async {
                self.date.addTimeInterval(self.timeInterval)
            }
        }
        return queue.sync {
            return date
        }
    }

    /// Pushes time forward by given number of seconds.
    func advance(bySeconds seconds: TimeInterval) {
        queue.async {
            self.date = self.date.addingTimeInterval(seconds)
        }
    }
}

extension HTTPClient {
    static func mockAny() -> HTTPClient {
        return HTTPClient(session: URLSession(configuration: URLSessionConfiguration.default), debug: false)
    }
}

/// A `DataUploaderType` backed by a `MockHTTPClient` so worker/uploader tests
/// can keep using `MockHTTPClient.waitAndReturnRequests(...)`. Wraps each
/// upload in a `URLRequest` carrying the raw batch as its `httpBody`.
internal struct MockClosureDataUploader: DataUploaderType {
    let httpClient: MockHTTPClient
    let url: URL

    init(httpClient: MockHTTPClient, url: URL = .mockAny()) {
        self.httpClient = httpClient
        self.url = url
    }

    func upload(data: Data) -> DataUploadStatus {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        let httpClient = self.httpClient
        do {
            let response = try waitForAsync { [request] () async throws(HTTPClient.RequestError) -> HTTPURLResponse in
                try await httpClient.send(request: request)
            }
            return DataUploadStatus(httpResponse: response)
        } catch {
            return DataUploadStatus(api: .init(from: error))
        }
    }
}

extension Device {
    static func mockAny() -> Device {
        return .mockWith()
    }

    static func mockWith(
        model: String = .mockAny(),
        osName: String = .mockAny(),
        osVersion: String = .mockAny()
    ) -> Device {
        return Device(
            model: model,
            osName: osName,
            osVersion: osVersion
        )
    }
}

struct DataUploaderMock: DataUploaderType {
    let uploadStatus: DataUploadStatus

    var onUpload: (() -> Void)? = nil

    func upload(data: Data) -> DataUploadStatus {
        onUpload?()
        return uploadStatus
    }
}

// MARK: - ExporterConfiguration / APIServiceConfig builders

extension ExporterConfiguration {
    /// Test-only convenience builder. Production callers build the
    /// `ExporterConfiguration` directly.
    static func mock(environment: String = "environment",
                     metadata: SpanMetadata = .init(),
                     performancePreset: PerformancePreset = .default,
                     logger: Logger = Log()) -> ExporterConfiguration
    {
        ExporterConfiguration(environment: environment,
                              metadata: metadata,
                              performancePreset: performancePreset,
                              logger: logger)
    }
}

extension APIServiceConfig {
    /// Test-only convenience builder for the now-test-private API config.
    static func mock(serviceName: String = "service",
                     environment: String = "environment",
                     applicationName: String = "app",
                     version: String = "1.0",
                     hostname: String? = nil,
                     apiKey: String = "apikey",
                     endpoint: Endpoint = .us1,
                     clientId: String = "client",
                     payloadCompression: Bool = false) -> APIServiceConfig
    {
        APIServiceConfig(serviceName: serviceName, environment: environment,
                         applicationName: applicationName, version: version,
                         device: .current, hostname: hostname, apiKey: apiKey,
                         endpoint: endpoint, clientId: clientId,
                         payloadCompression: payloadCompression)
    }
}

extension TelemetryApiService {
    static func mock(endpoint: Endpoint = .us1, logger: Logger = Log()) -> TelemetryApiService {
        TelemetryApiService(config: APIServiceConfig.mock(endpoint: endpoint),
                            httpClient: HTTPClient(debug: false),
                            dateProvider: SystemDateProvider(),
                            log: logger)
    }
}

extension TestOptimizationApiService {
    /// Test-only convenience builder. Production callers build the
    /// `TestOptimizationApiService` directly.
    static func mock(serviceName: String = "service",
                     environment: String = "environment",
                     applicationName: String = "app",
                     version: String = "1.0",
                     hostname: String? = nil,
                     apiKey: String = "apikey",
                     endpoint: Endpoint = .us1,
                     clientId: String = "client",
                     payloadCompression: Bool = false,
                     logger: Logger = Log()) -> TestOptimizationApiService
    {
        TestOptimizationApiService(serviceName: serviceName, environment: environment,
                                   applicationName: applicationName, version: version,
                                   hostname: hostname, apiKey: apiKey,
                                   endpoint: endpoint, clientId: clientId,
                                   payloadCompression: payloadCompression,
                                   logger: logger)
    }
}

extension DataUploadStatus: RandomMockable {
    static func mockRandom() -> DataUploadStatus {
        return DataUploadStatus(needsRetry: .random(), waitTime: nil)
    }

    static func mockWith(
        needsRetry: Bool = .mockAny(),
        waitTime: TimeInterval? = nil,
        accepted: Bool = true
    ) -> DataUploadStatus {
        return DataUploadStatus(needsRetry: needsRetry, waitTime: waitTime)
    }
}
