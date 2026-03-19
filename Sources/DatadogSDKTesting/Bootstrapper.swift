//
//  SessionProvider.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 19/03/2026.
//

import Foundation
internal import EventsExporter

struct SessionConfig {
    let activeFeatures: [any TestHooksFeature]
    let clock: Clock
    let crash: CrashedModuleInformation?
}

final actor SessionBootstrapper: TestSessionProvider {
    typealias SessionWithConfig = (session: any TestModuleProvider & TestSession, config: SessionConfig)
    
    private var _session: Task<SessionWithConfig, any Error>?
    let log: Logger
    
    init(log: Logger) {
        self._session = nil
        self.log = log
    }
    
    func startSession() async throws -> SessionWithConfig {
        if let session = _session {
            return try await session.value
        }
        _session = Task.detached { try await self.bootstrapSession() }
        return try await _session!.value
    }
    
    func bootstrapSession() async throws -> SessionWithConfig {
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
            clock: DDTestMonitor.clock,
            crash: monitor.crashedModuleInfo
        )
        
        let session = Session(name: "swift.session", config: config, command: DDTestMonitor.env.testCommand, startTime: startTime)
        return (session, config)
    }
}

extension SessionBootstrapper {
    enum BoostrapError: Error {
        case monitorInitFailed
        case monitorIsNil
    }
}
