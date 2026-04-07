/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final actor SessionManager: TestSessionManager {
    typealias SessionWithConfig = (session: any TestModuleManager & TestSession,
                                   config: SessionConfig)
    
    private var _session: Task<SessionWithConfig, any Error>?
    let observer: (any TestSessionManagerObserver & TestModuleManagerObserver)?
    let provider: any TestSessionProvider
    let log: Logger
    
    init(log: Logger, provider: any TestSessionProvider, observer: (any TestSessionManagerObserver & TestModuleManagerObserver)?) {
        self._session = nil
        self.log = log
        self.provider = provider
        self.observer = observer
    }
    
    var sessionAndConfig: SessionWithConfig {
        get async throws {
            if let session = _session {
                return try await session.value
            }
            _session = Task.detached { try await self.bootstrapSession() }
            return try await _session!.value
        }
    }
    
    func stop() async {
        guard let session = try? await _session?.value else {
            return
        }
        await observer?.willFinish(session: session.session, with: session.config)
        _session = nil
        session.session.end()
        await observer?.didFinish(session: session.session, with: session.config)
        DDTestMonitor.removeTestMonitor()
        DDTestMonitor.tracer.flush()
    }
    
    private func bootstrapSession() async throws -> SessionWithConfig {
        do {
            try await DDTestMonitor.clock.sync()
        } catch {
            log.print("Clock sync failed: \(error)")
            DDTestMonitor.clock = DateClock()
        }
        
        let startTime = DDTestMonitor.clock.now
        
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
        
        log.measure(name: "Setup crash handler") {
            monitor.setupCrashHandler()
        }
        
        let config = SessionConfig(
            activeFeatures: monitor.activeFeatures,
            workspacePath: DDTestMonitor.env.workspacePath,
            codeOwners: monitor.codeOwners,
            bundleFunctions: monitor.bundleFunctionInfo,
            platform: DDTestMonitor.env.platform,
            clock: DDTestMonitor.clock,
            crash: monitor.crashInfo,
            command: DDTestMonitor.env.testCommand,
            service: DDTestMonitor.env.service,
            metrics: DDTestMonitor.env.baseMetrics,
            log: log
        )
        
        let session = try await provider.startSession(named: "Swift.session", config: config,
                                                      startTime: startTime, observer: observer)
        await observer?.didStart(session: session, with: config)
        return (session, config)
    }
}

extension SessionManager {
    enum BoostrapError: Error {
        case monitorInitFailed
        case monitorIsNil
    }
}

extension Session {
    struct Provider: TestSessionProvider {
        func startSession(named name: String, config: SessionConfig, startTime: Date,
                          observer: (any TestModuleManagerObserver)?) async throws -> any TestModuleManager & TestSession
        {
            Session(name: name, config: config,
                    modules: Module.StatefulManager(config: config,
                                                    observer: observer),
                    startTime: startTime)
        }
    }
}

protocol TestModuleManagerSession: Sendable {
    func module(named: String, at: Date?, provider: any TestModuleProvider) -> any TestModule & TestSuiteProvider
    func end(module: any TestModule, at: Date?)
    func stop()
}

extension Module {
    struct StatelessManager: TestModuleManagerSession, Sendable {
        let config: SessionConfig
        let observer: (any TestModuleManagerObserver)?
        
        init(config: SessionConfig, observer: (any TestModuleManagerObserver)?) {
            self.config = config
            self.observer = observer
        }
        
        func module(named name: String,
                    at start: Date?,
                    provider: any TestModuleProvider) -> any TestModule & TestSuiteProvider
        {
            let module = provider.startModule(named: name, at: start)
            observer?.didStart(module: module, with: config)
            return module
        }
        
        func end(module: any TestModule, at end: Date?) {
            observer?.willFinish(module: module, with: config)
            module.end(time: end)
            observer?.didFinish(module: module, with: config)
        }
        
        func stop() {}
    }
    
    struct StatefulManager: TestModuleManagerSession, @unchecked Sendable {
        private let _state: Synced<[String: (module: any TestModule & TestSuiteProvider, end: Date?)]>
        let config: SessionConfig
        let observer: (any TestModuleManagerObserver)?
        
        init(config: SessionConfig, observer: (any TestModuleManagerObserver)?) {
            self._state = .init([:])
            self.config = config
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
                observer?.didStart(module: module, with: config)
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
                observer?.willFinish(module: module.module, with: config)
                module.module.end(time: module.end)
                observer?.didFinish(module: module.module, with: config)
            }
        }
    }
}

