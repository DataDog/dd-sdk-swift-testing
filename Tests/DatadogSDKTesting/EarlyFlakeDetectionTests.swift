/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
@testable import EventsExporter
import OpenTelemetryApi
import OpenTelemetrySdk
import CodeCoverage
import XCTest

final class EarlyFlakeDetectionTests: XCTestCase {
    var testObserver: DDTestObserver!
    var observers: NSMutableArray!
    private var validate: ((MockEventExporter) -> Void)!

    override func setUp() {
        XCTAssertNil(DDTracer.activeSpan)
        DDTestMonitor._env_recreate(env: [
            "DD_API_KEY": "fakeToken",
            "DD_DISABLE_TEST_INSTRUMENTING": "1",
            "DD_TRACE_DEBUG_CODE_COVERAGE": "0",
            "DD_DISABLE_CRASH_HANDLER": "1"
        ])
        EFDTest.reset()
        observers = XCTestObservationCenter.shared.value(forKey: "observers") as? NSMutableArray
        XCTestObservationCenter.shared.setValue(NSMutableArray(), forKey: "observers")
        testObserver = DDTestObserver()
        testObserver.start()
    }

    override func tearDown() {
        try? DDTestMonitor.cacheManager?.sessionDir?.delete()
        testObserver.stop()
        testObserver = nil
        XCTestObservationCenter.shared.setValue(observers, forKey: "observers")
        observers = nil
        let exporter = DDTestMonitor.tracer.eventsExporter as! MockEventExporter
        validate(exporter)
        validate = nil
        EFDTest.reset()
        DDTestMonitor._env_recreate()
        DDTestMonitor.cacheManager = try? CacheManager(environment: DDTestMonitor.env.environment,
                                                       session: DDTestMonitor.sessionId,
                                                       commit: DDTestMonitor.env.git.commitSHA,
                                                       debug: DDTestMonitor.config.extraDebugCodeCoverage)
        DDTestMonitor.tracer = DDTracer()
        XCTAssertNil(DDTracer.activeSpan)
    }
    
    func testEfdRetriesNewTest() {
        DDTestMonitor.tracer = tracer(atr: false, efd: true, knownTests: known(tests: [:]))
        
        testObserver.testBundleWillStart(Bundle.main)
        EFDTest.suite(failCount: 3).run()
        testObserver.testBundleDidFinish(Bundle.main)
        
        validate = { exporter in
            XCTAssertEqual(exporter.spans.count, 10)
            XCTAssertEqual(exporter.spans.filter { $0.status.isError }.count, 3)
        }
    }
    
    func testEfdRetriesNewSuccessTest() {
        DDTestMonitor.tracer = tracer(atr: false, efd: true, knownTests: known(tests: [:]))
        
        testObserver.testBundleWillStart(Bundle.main)
        EFDTest.suite(failCount: 0).run()
        testObserver.testBundleDidFinish(Bundle.main)
        
        validate = { exporter in
            XCTAssertEqual(exporter.spans.count, 10)
            XCTAssertEqual(exporter.spans.filter { $0.status.isError }.count, 0)
        }
    }
    
    func testEfdDoesntRetryOldTest() {
        DDTestMonitor.tracer = tracer(atr: false, efd: true,
                                      knownTests: known(tests: ["\(EFDTest.self)": "testMethod"]))
        
        testObserver.testBundleWillStart(Bundle.main)
        EFDTest.suite(failCount: 3).run()
        testObserver.testBundleDidFinish(Bundle.main)
        
        validate = { exporter in
            XCTAssertEqual(exporter.spans.count, 1)
            XCTAssertEqual(exporter.spans.filter { $0.status.isError }.count, 1)
        }
    }
    
    func testAtrRetriesFailedTest() {
        DDTestMonitor.tracer = tracer(atr: true, efd: false,
                                      knownTests: known(tests: [:]))
        
        testObserver.testBundleWillStart(Bundle.main)
        EFDTest.suite(failCount: 4).run()
        testObserver.testBundleDidFinish(Bundle.main)
        
        validate = { exporter in
            XCTAssertEqual(exporter.spans.count, 5)
            XCTAssertEqual(exporter.spans.filter { $0.status.isError }.count, 4)
        }
    }
    
    func testAtrDoesntRetryPassedTest() {
        DDTestMonitor.tracer = tracer(atr: true, efd: false,
                                      knownTests: known(tests: [:]))
        
        testObserver.testBundleWillStart(Bundle.main)
        EFDTest.suite(failCount: 0).run()
        testObserver.testBundleDidFinish(Bundle.main)
        
        validate = { exporter in
            XCTAssertEqual(exporter.spans.count, 1)
            XCTAssertEqual(exporter.spans.filter { $0.status.isError }.count, 0)
        }
    }
    
    func testAtrWorksWithEFDForOldTest() {
        DDTestMonitor.tracer = tracer(atr: true, efd: true,
                                      knownTests: known(tests: ["\(EFDTest.self)": "testMethod"]))
        
        testObserver.testBundleWillStart(Bundle.main)
        EFDTest.suite(failCount: 3).run()
        EFDTest2.suite().run()
        testObserver.testBundleDidFinish(Bundle.main)
        
        validate = { exporter in
            XCTAssertEqual(exporter.spans.count, 14)
            XCTAssertEqual(exporter.spans.filter { $0.status.isError }.count, 3)
        }
    }
    
    func testEFDDisablesATRForNewTest() {
        DDTestMonitor.tracer = tracer(atr: true, efd: true,
                                      knownTests: known(tests: ["\(EFDTest2.self)": "testMethod"]))
        
        testObserver.testBundleWillStart(Bundle.main)
        EFDTest.suite(failCount: 5).run()
        EFDTest2.suite().run()
        testObserver.testBundleDidFinish(Bundle.main)
        
        validate = { exporter in
            XCTAssertEqual(exporter.spans.count, 11)
            XCTAssertEqual(exporter.spans.filter { $0.status.isError }.count, 5)
        }
    }
    
    private func known(tests: KeyValuePairs<String, String>) -> KnownTestsMap {
        var combined = tests.reduce(into: [:]) { dict, pair in
            dict.get(key: pair.key, or: []) { arr in
                arr.append(pair.value)
            }
        }
        // Empty response will cancel EFD. Add some unexistent test
        combined[String(describing: Self.self)] = ["testMethod"]
        return [Bundle.main.name: combined]
    }
    
    private func tracer(atr: Bool, efd: Bool, knownTests: KnownTestsMap) -> DDTracer {
        DDTracer(id: "some-id", version: "1.0.0",
                 exporter: MockEventExporter(atr: atr, efd: efd, knownTests: knownTests),
                 enabled: true, launchContext: nil)
    }
}

private extension EarlyFlakeDetectionTests {
    final class EFDTest: XCTestCase {
        // Instance will be recreated. So they are static
        static var runCount: Int = 0
        static var failCount: Int = 0
        
        override var name: String { "-[\(Self.self) testMethod]" }
        
        func testMethod() {
            Self.runCount += 1
            XCTAssert(Self.runCount > Self.failCount, "Fail \(Self.runCount)")
        }
        
        static func reset() {
            Self.runCount = 0
            Self.failCount = 0
        }
        
        static func suite(failCount: Int) -> XCTestSuite {
            let test = Self(selector: #selector(testMethod))
            Self.failCount = failCount
            Self.runCount = 0
            let suite = XCTestSuite(name: "\(Self.self)")
            suite.addTest(test)
            return suite
        }
    }
    
    final class EFDTest2: XCTestCase {
        override var name: String { "-[\(Self.self) testMethod]" }
        
        func testMethod() {}
        
        static func suite() -> XCTestSuite {
            let test = Self(selector: #selector(testMethod))
            let suite = XCTestSuite(name: "\(Self.self)")
            suite.addTest(test)
            return suite
        }
    }
    
    
    final class MockEventExporter: EventsExporterProtocol {
        var atr: Bool
        var efd: Bool
        var knownTests: KnownTestsMap
        
        var events: [any Encodable] = []
        var spans: [SpanData] = []
        
        init(atr: Bool, efd: Bool, knownTests: KnownTestsMap) {
            self.atr = atr
            self.efd = efd
            self.knownTests = knownTests
        }
        
        var eventsSuiteEnd: [DDTestSuite.DDTestSuiteEnvelope] {
            events.compactMap { $0 as? DDTestSuite.DDTestSuiteEnvelope }
        }
        
        var eventsModuleEnd: [DDTestModule.DDTestModuleEnvelope] {
            events.compactMap { $0 as? DDTestModule.DDTestModuleEnvelope }
        }
        
        var eventsSessionEnd: [DDTestSession.DDTestSessionEnvelope] {
            events.compactMap { $0 as? DDTestSession.DDTestSessionEnvelope }
        }
        
        var endpointURLs: Set<String> { Set() }
        
        func searchCommits(repositoryURL: String, commits: [String]) -> [String] { [] }
        
        func uploadPackFiles(packFilesDirectory: Directory, commit: String, repository: String) throws { }
        
        func skippableTests(repositoryURL: String, sha: String, testLevel: ITRTestLevel,
                            configurations: [String: String], customConfigurations: [String: String]) -> SkipTests?
        {
            nil
        }
        
        func tracerSettings(service: String, env: String, repositoryURL: String, branch: String, sha: String,
                            testLevel: ITRTestLevel, configurations: [String: String], customConfigurations: [String: String]) -> TracerSettings?
        {
            TracerSettings(attrs: .init(itrEnabled: false, codeCoverage: false, testsSkipping: false,
                                        knownTestsEnabled: knownTests.count > 0, requireGit: false,
                                        flakyTestRetriesEnabled: self.atr,
                                        earlyFlakeDetection: .init(enabled: self.efd,
                                                                   slowTestRetries: ["5s": 10, "30s": 5, "1m": 2, "5m": 1],
                                                                   faultySessionThreshold: 30)))
        }
        
        func knownTests(service: String, env: String, repositoryURL: String,
                        configurations: [String : String], customConfigurations: [String : String]) -> KnownTestsMap? {
            knownTests
        }
        
        func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
            self.spans.append(contentsOf: spans)
            return .success
        }
        
        func exportEvent<T>(event: T) where T: Encodable {
            events.append(event)
        }
        
        func export(coverage: URL, processor: CodeCoverage.CoverageProcessor,
                    workspacePath: String?, testSessionId: UInt64,
                    testSuiteId: UInt64, spanId: UInt64) {}
        
        func shutdown(explicitTimeout: TimeInterval?) { }
        
        func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
            .success
        }
    }
}
