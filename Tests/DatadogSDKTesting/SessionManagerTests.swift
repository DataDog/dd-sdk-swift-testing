/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

final class SessionManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DDTestMonitor._env_recreate(env: [
            "DD_API_KEY": "fakeToken",
            "DD_DISABLE_TEST_INSTRUMENTING": "1",
            "DD_DISABLE_CRASH_HANDLER": "1"
        ])
    }

    override func tearDown() {
        DDTestMonitor.removeTestMonitor()
        DDTestMonitor._env_recreate()
        super.tearDown()
    }

    // MARK: - Session bootstrapping

    func testSessionIsLazilyInitialized() async throws {
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: nil)
        let session1 = try await manager.session
        let session2 = try await manager.session
        XCTAssertTrue(session1.id == session2.id)
        await manager.stop()
    }

    func testSessionConfigIsAvailableAfterBootstrap() async throws {
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: nil)
        let config1 = try await manager.config
        let config2 = try await manager.config
        XCTAssertEqual(config1.service, config2.service)
        await manager.stop()
    }

    // MARK: - Observer management

    func testObserverIsNotifiedWhenSessionStarts() async throws {
        let observer = MockObserver()
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: observer)

        _ = try await manager.session

        XCTAssertEqual(observer.didStartCount, 1)
        XCTAssertEqual(observer.didFinishCount, 0)
        await manager.stop()
    }

    func testObserverIsNotifiedWithCorrectSession() async throws {
        let observer = MockObserver()
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: observer)

        let session = try await manager.session
        await manager.stop()

        XCTAssertEqual(observer.lastStartedSession?.id, session.id)
        XCTAssertEqual(observer.lastFinishedSession?.id, session.id)
    }

    // MARK: - Stop behaviour

    func testStopWithNoBootstrappedSessionDoesNothing() async {
        let observer = MockObserver()
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: observer)
        // Must not crash and observer must not be notified
        await manager.stop()
        XCTAssertEqual(observer.didFinishCount, 0)
    }

    func testStopNotifiesObserversOfFinish() async throws {
        let observer = MockObserver()
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: observer)
        _ = try await manager.session

        await manager.stop()

        XCTAssertEqual(observer.didFinishCount, 1)
    }

    func testStopClearsSessionSoNextAccessCreatesNewOne() async throws {
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: nil)
        let session1 = try await manager.session
        await manager.stop()

        let session2 = try await manager.session
        XCTAssertFalse(session1.id == session2.id)
        await manager.stop()
    }
}

// MARK: - Test helpers

private final class MockObserver: TestSessionManagerObserver, TestModuleManagerObserver, @unchecked Sendable {
    private let _state: Synced<State> = .init(.init())

    struct State {
        var didStartCount: Int = 0
        var didFinishCount: Int = 0
        var lastStartedSession: (any TestSession)?
        var lastFinishedSession: (any TestSession)?
    }

    var didStartCount: Int { _state.value.didStartCount }
    var didFinishCount: Int { _state.value.didFinishCount }
    var lastStartedSession: (any TestSession)? { _state.value.lastStartedSession }
    var lastFinishedSession: (any TestSession)? { _state.value.lastFinishedSession }

    func didStart(session: any TestSession, with config: SessionConfig) async {
        _state.update {
            $0.didStartCount += 1
            $0.lastStartedSession = session
        }
    }

    func willFinish(session: any TestSession, with config: SessionConfig) async {}

    func didFinish(session: any TestSession, with config: SessionConfig) async {
        _state.update {
            $0.didFinishCount += 1
            $0.lastFinishedSession = session
        }
    }

    func didStart(module: any TestModule, with config: SessionConfig) {}
    func willFinish(module: any TestModule, with config: SessionConfig) {}
    func didFinish(module: any TestModule, with config: SessionConfig) {}
}
