/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

/// Owns the lifecycle of the one test session and, through it, the teardown of
/// `DDTestMonitor`.
///
/// State is guarded by a lock rather than actor isolation on purpose: teardown
/// has to be reachable synchronously from the library-unload C destructor during
/// `exit()`, where the Swift cooperative executor is no longer guaranteed to run
/// — so a `Task`/`await` hop there can deadlock instead of completing.
final class SessionManager: TestSessionManager, @unchecked Sendable {
    typealias Session = any TestModuleManager & TestSession

    private enum State {
        case idle
        case starting(Task<Session, any Error>)
        case running(Session)
    }

    private let state: Synced<State>
    let observer: (any TestSessionManagerObserver & TestModuleManagerObserver)?
    let provider: any TestSessionProvider
    let bootstrap: Bootstrap
    let log: Logger

    init(log: Logger, provider: any TestSessionProvider,
         observer: (any TestSessionManagerObserver & TestModuleManagerObserver)?,
         bootstrap: Bootstrap = .automatic) {
        self.state = Synced(.idle)
        self.log = log
        self.provider = provider
        self.observer = observer
        self.bootstrap = bootstrap
    }

    var session: Session {
        get async throws {
            switch pendingSession() {
            case .ready(let session):
                return session
            case .starting(let task):
                let session = try await task.value
                state.update { state in
                    if case .starting = state { state = .running(session) }
                }
                return session
            }
        }
    }

    func stop() async {
        guard let session = await takeSession() else { return }
        await observer?.willFinish(session: session)
        session.end(time: nil)
        await observer?.didFinish(session: session)
        await DDTestMonitor.removeTestMonitor()
    }

    /// Synchronous teardown for the process-exit path. Contains no `Task`/`await`
    /// at any depth: the observer hooks run, the session's span is ended and the
    /// monitor is shut down, all on the calling thread.
    func stop() {
        switch takeSessionSync() {
        case .none:
            return
        case .session(let session):
            observer?.willFinish(session: session)
            session.end(time: nil)
            observer?.didFinish(session: session)
        case .stillStarting:
            // The session never finished bootstrapping, so there's no span to
            // end — but still shut the monitor down so whatever was already
            // gathered gets flushed and uploaded.
            log.debug("Session was still starting at teardown; shutting down without ending it")
        }
        // `removeTestMonitor()` runs the monitor's `stop()` (which flushes and
        // shuts the tracer down) and then releases the instance, at which point
        // `DDTracer.deinit` restores the default OpenTelemetry providers.
        DDTestMonitor.removeTestMonitor()
    }

    // MARK: - State transitions

    private enum PendingSession {
        case ready(Session)
        case starting(Task<Session, any Error>)
    }

    /// Returns the live session, or the task bootstrapping it — starting the
    /// bootstrap when this is the first access.
    private func pendingSession() -> PendingSession {
        state.update { state in
            switch state {
            case .running(let session):
                return .ready(session)
            case .starting(let task):
                return .starting(task)
            case .idle:
                let task = Task.detached { try await self.bootstrapSession() }
                state = .starting(task)
                return .starting(task)
            }
        }
    }

    /// Detaches the session from the manager so it can be ended exactly once.
    private func takeSession() async -> Session? {
        let pending: PendingSession? = state.update { state in
            defer { state = .idle }
            switch state {
            case .running(let session): return .ready(session)
            case .starting(let task): return .starting(task)
            case .idle: return nil
            }
        }
        switch pending {
        case .ready(let session): return session
        case .starting(let task): return try? await task.value
        case nil: return nil
        }
    }

    private enum SyncTakeResult {
        case session(Session)
        case stillStarting
        case none
    }

    private func takeSessionSync() -> SyncTakeResult {
        state.update { state in
            switch state {
            case .running(let session):
                state = .idle
                return .session(session)
            case .starting:
                state = .idle
                return .stillStarting
            case .idle:
                return .none
            }
        }
    }

    private func bootstrapSession() async throws -> any TestModuleManager & TestSession {
        await DDTestMonitor.clock.sync()

        let startTime = bootstrap.startTime ?? DDTestMonitor.clock.now

        if DDTestMonitor.instance == nil {
            try log.measure(name: "Install Test Monitor") {
                guard DDTestMonitor.installTestMonitor() else {
                    throw BoostrapError.monitorInitFailed
                }
            }
        }

        guard let monitor = DDTestMonitor.instance else {
            throw BoostrapError.monitorIsNil
        }

        if bootstrap.installsCrashHandler {
            log.measure(name: "Setup crash handler") {
                monitor.setupCrashHandler()
            }
        }

        // The common telemetry manager is created with the tracer (so it's
        // available to the API/exporter layers) and shared with every feature
        // through the session config. `nil` when telemetry is disabled.
        let config = SessionConfig(
            activeFeatures: monitor.activeFeatures,
            env: DDTestMonitor.env,
            config: DDTestMonitor.config,
            clock: DDTestMonitor.clock,
            crash: monitor.crashInfo,
            command: bootstrap.command.value,
            log: log,
            tracer: monitor.tracer,
            telemetry: monitor.tracer.telemetry
        )

        let session = try await provider.startSession(named: bootstrap.sessionName, config: config,
                                                      startTime: startTime, observer: observer,
                                                      manager: self)
        await observer?.didStart(session: session)
        return session
    }
}

extension SessionManager {
    enum BoostrapError: Error {
        case monitorInitFailed
        case monitorIsNil
    }

    /// What differs between the framework-driven bootstrap and the manual
    /// `DDSession.start` API.
    struct Bootstrap: Sendable {
        enum Command: Sendable {
            case environment
            case explicit(String?)

            var value: String? {
                switch self {
                case .environment: return DDTestMonitor.env.testCommand
                case .explicit(let command): return command
                }
            }
        }

        let sessionName: String
        let command: Command
        /// `nil` uses the clock's time at bootstrap.
        let startTime: Date?
        let installsCrashHandler: Bool

        /// Framework-driven runs (XCTest / swift-testing).
        static let automatic = Bootstrap(sessionName: "Swift.session", command: .environment,
                                         startTime: nil, installsCrashHandler: true)

        /// The manual API. It has never installed the crash handler, so it still
        /// doesn't — enabling it here would turn crash reporting on for embedders
        /// that only use `DDSession.start`.
        static func manual(name: String, command: String?, startTime: Date?) -> Bootstrap {
            Bootstrap(sessionName: name, command: .explicit(command),
                      startTime: startTime, installsCrashHandler: false)
        }
    }
}

extension DDSession {
    /// Framework-driven sessions. The `SessionManager` that created them ends them
    /// directly, so they don't hold a back-reference to it.
    struct Provider: TestSessionProvider {
        func startSession(named name: String, config: SessionConfig, startTime: Date,
                          observer: (any TestModuleManagerObserver)?,
                          manager: any TestSessionManager) async throws -> any TestModuleManager & TestSession
        {
            DDSession(name: name, config: config,
                      modules: DDModule.StatefulManager(observer: observer),
                      startTime: startTime)
        }
    }

    /// Sessions created through the public `DDSession.start` API. The caller ends
    /// these, so the session keeps the manager that performs the shutdown.
    struct ManualProvider: TestSessionProvider {
        func startSession(named name: String, config: SessionConfig, startTime: Date,
                          observer: (any TestModuleManagerObserver)?,
                          manager: any TestSessionManager) async throws -> any TestModuleManager & TestSession
        {
            DDSession(name: name, config: config,
                      modules: DDModule.StatelessManager(observer: observer),
                      startTime: startTime,
                      sessionManager: manager)
        }
    }
}

protocol TestModuleManagerSession: Sendable {
    func module(named: String, at: Date?, provider: any TestModuleProvider) -> any TestModule & TestSuiteProvider
    func end(module: any TestModule, at: Date?)
    func stop()
}

extension DDModule {
    struct StatelessManager: TestModuleManagerSession, Sendable {
        let observer: (any TestModuleManagerObserver)?

        init(observer: (any TestModuleManagerObserver)?) {
            self.observer = observer
        }

        func module(named name: String,
                    at start: Date?,
                    provider: any TestModuleProvider) -> any TestModule & TestSuiteProvider
        {
            let module = provider.startModule(named: name, at: start)
            observer?.didStart(module: module)
            return module
        }

        func end(module: any TestModule, at end: Date?) {
            observer?.willFinish(module: module)
            module.end(time: end)
            observer?.didFinish(module: module)
        }
        
        func stop() {}
    }
    
    struct StatefulManager: TestModuleManagerSession, @unchecked Sendable {
        private let _state: Synced<[String: (module: any TestModule & TestSuiteProvider, end: Date?)]>
        let observer: (any TestModuleManagerObserver)?

        init(observer: (any TestModuleManagerObserver)?) {
            self._state = .init([:])
            self.observer = observer
        }
        
        func module(named name: String,
                    at start: Date?,
                    provider: any TestModuleProvider) -> any TestModule & TestSuiteProvider
        {
            let (module, started) = _state.update { state in
                if let module = state[name] {
                    return (module.module, false)
                }
                let module = provider.startModule(named: name, at: start)
                state[name] = (module, nil)
                return (module, true)
            }
            if started {
                observer?.didStart(module: module)
            }
            return module
        }
        
        func end(module: any TestModule, at end: Date?) {
            guard let end else { return }
            _state.update {
                if ($0[module.name]?.end ?? .distantPast) < end {
                    $0[module.name]?.end = end
                }
            }
        }
        
        func stop() {
            let modules = _state.update { state in
                let modules = state
                state = [:]
                return modules
            }
            for module in modules.values {
                observer?.willFinish(module: module.module)
                module.module.end(time: module.end)
                observer?.didFinish(module: module.module)
            }
        }
    }
}

