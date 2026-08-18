/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
@testable import EventsExporter
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
        let config1 = try await manager.session.configuration
        let config2 = try await manager.session.configuration
        XCTAssertEqual(config1.env.service, config2.env.service)
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

    // MARK: - Synchronous stop (process-exit path)

    func testSyncStopEndsBootstrappedSession() async throws {
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: nil)
        let session = try await manager.session

        stopSynchronously(manager)

        XCTAssertNotEqual(session.duration, 0, "The session's span should have been ended")
    }

    func testSyncStopNotifiesObserversOfFinish() async throws {
        let observer = MockObserver()
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: observer)
        let session = try await manager.session

        stopSynchronously(manager)

        XCTAssertEqual(observer.didFinishCount, 1, "The end hooks must run on the sync path too")
        XCTAssertEqual(observer.willFinishCount, 1)
        XCTAssertEqual(observer.lastFinishedSession?.id, session.id)
    }

    func testSyncStopWithNoBootstrappedSessionDoesNothing() {
        let observer = MockObserver()
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: observer)

        manager.stop()

        XCTAssertEqual(observer.didFinishCount, 0)
    }

    func testSyncStopClearsSessionSoNextAccessCreatesNewOne() async throws {
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: nil)
        let session1 = try await manager.session

        stopSynchronously(manager)

        let session2 = try await manager.session
        XCTAssertFalse(session1.id == session2.id)
        stopSynchronously(manager)
    }

    func testSyncStopIsIdempotent() async throws {
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(), observer: nil)
        let session = try await manager.session

        stopSynchronously(manager)
        let duration = session.duration
        stopSynchronously(manager)

        XCTAssertEqual(session.duration, duration, "A second stop must not re-end the session")
    }

    // MARK: - Bootstrap options

    func testManualBootstrapUsesSuppliedNameCommandAndStartTime() async throws {
        let provider = Mocks.Session.Provider()
        let startTime = Date(timeIntervalSince1970: 1_000_000)
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: provider, observer: nil,
                                     bootstrap: .manual(name: "Manual.session",
                                                        command: "my command",
                                                        startTime: startTime))

        let session = try await manager.session

        XCTAssertEqual(session.name, "Manual.session")
        XCTAssertEqual(session.startTime, startTime)
        XCTAssertEqual(session.configuration.command, "my command")
        await manager.stop()
    }

    func testManualBootstrapNotifiesObserverOfStart() async throws {
        let observer = MockObserver()
        let manager = SessionManager(log: Mocks.CatchLogger(), provider: Mocks.Session.Provider(),
                                     observer: observer,
                                     bootstrap: .manual(name: "Manual.session", command: nil,
                                                        startTime: nil))

        let session = try await manager.session

        XCTAssertEqual(observer.didStartCount, 1, "The manual path must fire didStart too")
        XCTAssertEqual(observer.lastStartedSession?.id, session.id)
        await manager.stop()
    }

    /// Calls the *synchronous* `stop()`. Needed inside `async` tests, where the
    /// compiler would otherwise resolve `stop()` to the `async` overload.
    private func stopSynchronously(_ manager: SessionManager) {
        manager.stop()
    }
}

// MARK: - Test helpers

private final class MockObserver: TestSessionManagerObserver, TestModuleManagerObserver, @unchecked Sendable {
    private let _state: Synced<State> = .init(.init())

    struct State {
        var didStartCount: Int = 0
        var willFinishCount: Int = 0
        var didFinishCount: Int = 0
        var lastStartedSession: (any TestSession)?
        var lastFinishedSession: (any TestSession)?
    }

    var didStartCount: Int { _state.value.didStartCount }
    var willFinishCount: Int { _state.value.willFinishCount }
    var didFinishCount: Int { _state.value.didFinishCount }
    var lastStartedSession: (any TestSession)? { _state.value.lastStartedSession }
    var lastFinishedSession: (any TestSession)? { _state.value.lastFinishedSession }

    func didStart(session: any TestSession) async {
        _state.update {
            $0.didStartCount += 1
            $0.lastStartedSession = session
        }
    }

    func willFinish(session: any TestSession) {
        _state.update { $0.willFinishCount += 1 }
    }

    func didFinish(session: any TestSession) {
        _state.update {
            $0.didFinishCount += 1
            $0.lastFinishedSession = session
        }
    }

    func didStart(module: any TestModule) {}
    func willFinish(module: any TestModule) {}
    func didFinish(module: any TestModule) {}
}
