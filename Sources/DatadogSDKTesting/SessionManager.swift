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
    private var _observers: [any TestSessionManagerObserver]
    let provider: any TestSessionProvider
    let log: Logger
    
    init(log: Logger, provider: any TestSessionProvider) {
        self._session = nil
        self.log = log
        self.provider = provider
        self._observers = []
    }
    
    var session: any TestModuleManager & TestSession {
        get async throws {
            try await _bootstrappedSession.session
        }
    }
    
    var sessionConfig: SessionConfig {
        get async throws {
            try await _bootstrappedSession.config
        }
    }
    
    func add(observer: any TestSessionManagerObserver) async {
        _observers.append(observer)
        if let session = try? await _session?.value {
            await observer.willStart(session: session.session, with: session.config)
        }
    }
    
    func remove(observer: any TestSessionManagerObserver) {
        _observers.removeAll { $0.id == observer.id }
    }
    
    func stop() async {
        guard let session = try? await _session?.value else {
            return
        }
        session.session.stopModules()
        session.session.end()
        _session = nil
        for observer in _observers {
            await observer.didFinish(session: session.session, with: session.config)
        }
        DDTestMonitor.removeTestMonitor()
        DDTestMonitor.tracer.flush()
    }
    
    private var _bootstrappedSession: SessionWithConfig {
        get async throws {
            if let session = _session {
                return try await session.value
            }
            _session = Task.detached { try await self.bootstrapSession() }
            return try await _session!.value
        }
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
        
        let session = try await provider.startSession(named: "Swift.session", config: config, startTime: startTime)
        for observer in _observers {
            await observer.willStart(session: session, with: config)
        }
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
        func startSession(named name: String, config: SessionConfig, startTime: Date) async throws -> any TestModuleManager & TestSession {
            Session(name: name, config: config,
                    modules: Module.StatefulManager(),
                    startTime: startTime)
        }
    }
}

protocol TestModuleManagerSession: Sendable {
    var moduleShouldEnd: Bool { get }
    
    func module(named: String, at: Date?, provider: any TestModuleProvider) -> any TestModule & TestSuiteProvider
    func stopModules()
}

extension Module {
    struct StatelessManager: TestModuleManagerSession, Sendable {
        let moduleShouldEnd: Bool = true
        
        func module(named name: String,
                    at start: Date?,
                    provider: any TestModuleProvider) -> any TestModule & TestSuiteProvider
        {
            provider.startModule(named: name, at: start)
        }
        
        func stopModules() {}
    }
    
    struct StatefulManager: TestModuleManagerSession, @unchecked Sendable {
        struct State {
            var modules: [String: any TestModule & TestSuiteProvider]
            var moduleShouldEnd: Bool
        }
        private let _state: Synced<State>
        var moduleShouldEnd: Bool { _state.value.moduleShouldEnd }
        
        init() {
            self._state = .init(.init(modules: [:], moduleShouldEnd: false))
        }
        
        func module(named name: String,
                    at start: Date?,
                    provider: any TestModuleProvider) -> any TestModule & TestSuiteProvider
        {
            _state.update { state in
                if let module = state.modules[name] {
                    return module
                }
                let module = provider.startModule(named: name, at: start)
                state.modules[name] = module
                return module
            }
        }
        
        func stopModules() {
            let modules = _state.update { state in
                state.moduleShouldEnd = true
                let modules = state.modules
                state.modules = [:]
                return modules
            }
            for module in modules.values {
                module.end(time: module.duration > 0 ? module.endTime : nil)
            }
        }
    }
}

