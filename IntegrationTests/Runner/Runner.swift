//
//  Builder.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 17/04/2026.
//

import Foundation
import Testing
@testable import DatadogSDKTesting

struct XcodeTestRunner: Sendable {
    enum RunnerError: Error {
        case processFailed(Int32)
        case traitIsNotAttached
    }
    
    actor Modules {
        var modules: [String: Task<Void, any Error>] = [:]
        var activeTests: [String: Task<Void, Never>] = [:]
        let backend: DDMockBackend = .init()
        var started: Bool = false
        
        func build(module: String) async -> Task<Void, any Error> {
            if let task = modules[module] {
                return task
            }
            let task = Task {
                print("note: >>>>>>>>>>>>>> IntegrationTestRunner: building \(module)... >>>>>>>>>>>>>>")
                let status = try await XcodeTestRunner.xcodebuild(module: module,
                                                                  action: ["build-for-testing"],
                                                                  server: nil)
                print("note: <<<<<<<<<<<<<< IntegrationTestRunner: build finished for \(module), status: \(status) <<<<<<<<<<<<<<")
                if status != 0 { throw RunnerError.processFailed(status) }
            }
            modules[module] = task
            return task
        }
        
        func runTest(module: String, test: String, config: DDMockBackend.Config = .init(),
                     _ function: @Sendable @escaping (DDMockBackend.Requests, Bool, DDMockBackend.Config) async throws -> Void) async throws
        {
            await activeTests[module]?.value
            let task = Task {
                if !self.started {
                    try self.backend.start()
                    self.started = true
                }
                self.backend.configuration = config
                let status = try await XcodeTestRunner.xcodebuild(module: module,
                                                                  action: ["-only-testing",
                                                                           "\(module)/\(test)",
                                                                           "test-without-building"],
                                                                  server: self.backend.baseURL)
                defer { self.backend.reset() }
                try await function(self.backend.requests, status == 0, self.backend.configuration)
            }
            activeTests[module] = Task { let _ = await task.result }
            try await task.value
        }
    }
    
    let module: String
    
    func build() async throws {
        try await Self.modules.build(module: module).value
    }
    
    func runTest(named: String, config: DDMockBackend.Config = .init(),
                 _ function: @Sendable @escaping (DDMockBackend.Requests, Bool, DDMockBackend.Config) async throws -> Void) async throws {
        try await build()
        try await Self.modules.runTest(module: module, test: named, config: config, function)
    }
    
    fileprivate func xcodebuild(action: [String], server: URL?) async throws -> Int32 {
        try await Self.xcodebuild(module: module, action: action, server: server)
    }
    
    fileprivate static func xcodebuild(module: String, action: [String], server: URL?) async throws -> Int32 {
        var env = ProcessInfo.processInfo.environment
        
        var sdk = env["INTEGRATION_TESTS_SDK"] ?? ""
        if sdk == "" {
            sdk = "macosx"
        }
        var platform = env["INTEGRATION_TESTS_PLATFORM"] ?? ""
        if platform == "" {
            platform = "platform=macOS,arch=arm64"
        }
        
        var log = env["INTEGRATION_TESTS_LOG_PATH"]
        if log == "" {
            log = nil
        }
        
        let workdir = env["SRCROOT"] ?? FileManager.default.currentDirectoryPath
        
        env["INTEGRATION_TESTS_SDK"] = nil
        env["INTEGRATION_TESTS_PLATFORM"] = nil
        env["INTEGRATION_TESTS_LOG_PATH"] = nil
        
        if let server {
            env[EnvironmentKey.customURL.rawValue] = server.absoluteString
            env[EnvironmentKey.apiKey.rawValue] = "abacabadabacabaeabacabadabacaba"
            env[EnvironmentKey.isEnabled.rawValue] = "true"
        } else {
            env[EnvironmentKey.customURL.rawValue] = nil
            env[EnvironmentKey.apiKey.rawValue] = nil
            env[EnvironmentKey.isEnabled.rawValue] = "false"
        }
        
        var stdOut = FileHandle.standardOutput
        var stdErr = FileHandle.standardError
        var shouldCloseStdOut: Bool = false
        if let log = log.map({ URL(fileURLWithPath: $0, isDirectory: true) }){
            let name = action.joined(separator: "_")
                .replacingOccurrences(of: "(", with: "_")
                .replacingOccurrences(of: ")", with: "_")
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let path =  log.appendingPathComponent("\(sdk)-\(module)-\(name).log")
            try Data().write(to: path)
            let file = try FileHandle(forWritingTo: path)
            stdOut = file
            stdErr = file
            shouldCloseStdOut = true
        }
        
        defer {
            if shouldCloseStdOut { try? stdOut.close() }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
        process.standardOutput = stdOut
        process.standardError = stdErr
        process.standardInput = FileHandle.standardInput
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: workdir, isDirectory: true)
        process.arguments = [
            "xcodebuild",
            "-scheme", module,
            "-sdk", sdk,
            "-destination", platform
        ] + action
        
        try process.run()
        
        await process.waitUntilExitAsync()
        return process.terminationStatus
    }
    
    static let modules: Modules = .init()
}


protocol IntergationTestSuite {}

extension IntergationTestSuite {
    func run(test name: String, config: DDMockBackend.Config = .init(),
             _ function: @Sendable @escaping (DDMockBackend.Requests, Bool, DDMockBackend.Config) async throws -> Void) async throws
    {
        guard let runner = BuildProvider.testRunner else {
            throw XcodeTestRunner.RunnerError.traitIsNotAttached
        }
        try await runner.runTest(named: name, config: config, function)
    }
    
    func run(test name: String, config: DDMockBackend.Config = .init(),
             _ function: @Sendable @escaping (DDMockBackend.Requests, Bool) async throws -> Void) async throws
    {
        try await run(test: name, config: config) { request, success, _ in
            try await function(request, success)
        }
    }
}

struct BuildProvider: SuiteTrait, TestScoping {
    let module: String
    
    func prepare(for test: Testing.Test) async throws {
        try await XcodeTestRunner(module: module).build()
    }
    
    func provideScope(for test: Testing.Test, testCase: Testing.Test.Case?,
                      performing function: @concurrent @Sendable () async throws -> Void) async throws
    {
        try await Self.$testRunner.withValue(XcodeTestRunner(module: module), operation: function)
    }
    
    @TaskLocal static var testRunner: XcodeTestRunner?
}

extension Trait where Self == BuildProvider {
    static func build(_ type: String) -> Self {
        .init(module: "IntegrationTests-\(type)")
    }
}

extension Process {
    func waitUntilExitAsync() async {
        await withCheckedContinuation { continuation in
            guard self.isRunning else {
                continuation.resume()
                return
            }

            self.terminationHandler = { _ in
                continuation.resume()
            }
        }
    }
}
