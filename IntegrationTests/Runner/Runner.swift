//
//  Builder.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 17/04/2026.
//

import Foundation
import Testing
import TestUtils
@testable import DatadogSDKTesting

struct XcodeTestRunner: Sendable {
    enum RunnerError: Error {
        case processFailed(Int32)
        case traitIsNotAttached
    }
    
    struct Config: Sendable {
        var backend: MockBackend.Config = .init()
        var environment: [String: String] = [:]
    }

    actor Modules {
        var modules: [String: Task<Void, any Error>] = [:]
        var activeTests: [String: Task<Void, Never>] = [:]
        var simulator: Task<Void, any Error>? = nil
        let backend: MockBackend = .init()
        var started: Bool = false

        func build(module: String) async -> Task<Void, any Error> {
            if let task = modules[module] {
                return task
            }
            let task = Task {
                print("note: [IntegrationTestRunner]: building \(module)...")
                let status = try await XcodeTestRunner.xcodebuild(module: module,
                                                                  action: ["build-for-testing"],
                                                                  environment: [:],
                                                                  server: nil)
                print("note: [IntegrationTestRunner]: build finished for \(module), status: \(status).")
                if status != 0 { throw RunnerError.processFailed(status) }
            }
            modules[module] = task
            return task
        }

        func runTest(module: String, testBundle: String, test: String, config: Config = .init(),
                     _ function: @Sendable @escaping (MockBackend.Requests, Bool, Config) async throws -> Void) async throws
        {
            await activeTests[module]?.value
            let task = Task {
                if !self.started {
                    try self.backend.start()
                    self.started = true
                }
                self.backend.configuration = config.backend
                print("note: [IntegrationTestRunner]: testing \(testBundle)/\(test)...")
                let status = try await XcodeTestRunner.xcodebuild(module: module,
                                                                  action: ["-only-testing",
                                                                           "\(testBundle)/\(test)",
                                                                           "test-without-building"],
                                                                  environment: config.environment,
                                                                  server: self.backend.baseURL)
                print("note: [IntegrationTestRunner]: test \(testBundle)/\(test) finished, status: \(status).")
                let requests = self.backend.requests
                defer { self.backend.reset() }
                // Propagate device/OS tags from the inner test process to the outer runner span.
                // The runner always executes on macOS; for simulator platforms the inner tests
                // carry the real simulator device info that would otherwise be absent.
                //
                // Device/OS tags live in the envelope-level metadata under "test_levels" — they
                // are NOT merged into individual span.meta by SpanEvent.extend (which only merges
                // metadata[span.type] and metadata["*"]), so we read the envelope metadata directly.
                // Individual span tags take priority over envelope metadata (span tags override).
                let deviceTagKeys = [DDOSTags.osPlatform, DDOSTags.osArchitecture, DDOSTags.osVersion,
                                     DDDeviceTags.deviceName, DDDeviceTags.deviceModel]
                if let envelope = requests.spanEnvelopes.first,
                   let envTags = envelope.metadata["test_levels"],
                   let osPlatform = envTags[DDOSTags.osPlatform],
                   osPlatform != "macOS",
                   let currentTest = DDTest.current
                {
                    for key in deviceTagKeys {
                        // Prefer a value set directly on an individual span (via allSpans extended
                        // merge), fall back to the envelope-level metadata value.
                        let value = requests.allSpans.lazy.compactMap({ $0.meta[key] }).first
                                    ?? envTags[key]
                        if let value {
                            currentTest.set(tag: key, value: value)
                        }
                    }
                }
                try await function(requests, status == 0, config)
            }
            activeTests[module] = Task { let _ = await task.result }
            try await task.value
        }
        
        func bootSimulator() async throws {
            if let simulator = simulator {
                return try await simulator.value
            }
            simulator = Task { try await XcodeTestRunner.bootSimulator() }
            try await simulator!.value
        }
    }

    let module: String
    let testBundle: String

    init(module: String, testBundle: String? = nil) {
        self.module = module
        self.testBundle = testBundle ?? module
    }
    
    func bootSimulator() async throws {
        try await Self.modules.bootSimulator()
    }

    func build() async throws {
        try await bootSimulator()
        try await Self.modules.build(module: module).value
    }
    
    func runTest(named: String, config: Config = .init(),
                 _ function: @Sendable @escaping (MockBackend.Requests, Bool, Config) async throws -> Void) async throws {
        try await build()
        try await Self.modules.runTest(module: module, testBundle: testBundle, test: named, config: config, function)
    }
    
    fileprivate func xcodebuild(action: [String], environment: [String: String], server: URL?) async throws -> Int32 {
        try await Self.xcodebuild(module: module, action: action, environment: environment, server: server)
    }
    
    fileprivate static func xcodebuild(module: String, action: [String], environment: [String: String], server: URL?) async throws -> Int32 {
        var env = ProcessInfo.processInfo.environment
        let (sdk, platform, workdir, log) = parameters(env: env)
        
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
        
        env.merge(environment) { old, new in new }
        
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
            print("note: [IntegrationTestRunner]: writing xcodebuild logs to: \(path.path)")
        }
        
        defer {
            if shouldCloseStdOut { try? stdOut.close() }
        }
        
        // Isolate inner xcodebuild DerivedData from the outer test bundle's.
        // When both share `~/Library/Developer/Xcode/DerivedData` the inner
        // SWBBuildService evicts cached build descriptions out from under
        // the outer process and prints duplicate-blueprint warnings; this
        // has caused random mid-build failures and aborted test sessions.
        let derivedDataPath = "\(workdir)/build/integration-DerivedData"

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
            "-destination", platform,
            "-derivedDataPath", derivedDataPath,
        ] + action
        
        try process.run()
        
        await process.waitUntilExitAsync()
        return process.terminationStatus
    }
    
    fileprivate static func bootSimulator() async throws {
        let env = ProcessInfo.processInfo.environment
        let platform = parameters(env: env).platform

        guard platform.contains("Simulator") else { return }

        let nameComponent = platform.split(separator: ",")
            .first(where: { $0.hasPrefix("name=") })
        guard let nameComponent else { return }
        let simulatorName = String(nameComponent.dropFirst("name=".count))

        print("note: [IntegrationTestRunner]: booting simulator '\(simulatorName)'...")

        let stderrPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
        process.arguments = ["xcrun", "simctl", "boot", simulatorName]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = stderrPipe
        try process.run()
        await process.waitUntilExitAsync()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        if !stderrText.isEmpty { FileHandle.standardError.write(stderrData) }

        let status = process.terminationStatus
        // Non-zero exit is OK if the simulator is already booted
        if status != 0 && !stderrText.contains("Booted") {
            throw RunnerError.processFailed(status)
        }

        print("note: [IntegrationTestRunner]: simulator '\(simulatorName)' is booted.")
    }
    
    fileprivate static func parameters(env: borrowing [String: String]) -> (sdk: String, platform: String, workdir: String, log: String?) {
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
        return (sdk, platform, workdir, log)
    }

    /// `true` when the child test bundle is being launched against a watchOS SDK
    /// (`watchos` device or `watchsimulator`). Used by tests to skip assertions
    /// that depend on platform features unavailable on watchOS — most notably
    /// KSCrash signal/mach exception handlers, which are disabled in KSCrash
    /// itself (`KSCRASH_HAS_SIGNAL = 0`, `KSCRASH_HAS_MACH = 0` on watchOS).
    static var isWatchOSChildSDK: Bool {
        parameters(env: ProcessInfo.processInfo.environment).sdk.hasPrefix("watch")
    }

    static let modules: Modules = .init()
}


protocol IntergationTestSuite {}

extension IntergationTestSuite {
    func run(test name: String, config: XcodeTestRunner.Config = .init(),
             _ function: @Sendable @escaping (MockBackend.Requests, Bool, XcodeTestRunner.Config) async throws -> Void) async throws
    {
        guard let runner = BuildProvider.testRunner else {
            throw XcodeTestRunner.RunnerError.traitIsNotAttached
        }
        try await runner.runTest(named: name, config: config, function)
    }
    
    func run(test name: String, config: XcodeTestRunner.Config = .init(),
             _ function: @Sendable @escaping (MockBackend.Requests, Bool) async throws -> Void) async throws
    {
        try await run(test: name, config: config) { request, success, _ in
            try await function(request, success)
        }
    }
}

struct BuildProvider: SuiteTrait, TestScoping {
    let module: String
    let testBundle: String

    init(module: String, testBundle: String? = nil) {
        self.module = module
        self.testBundle = testBundle ?? module
    }

    // Only boot the simulator in `prepare`. The actual `xcodebuild
    // build-for-testing` is deferred to `provideScope` because xcodebuild
    // gates the test-runner "ready to run" handshake on trait preparation
    // finishing within a short window (~5 minutes on Xcode 26). Inner
    // builds can run several minutes, so doing them here trips the
    // "test runner timed out while preparing to run tests" failure.
    func prepare(for test: Testing.Test) async throws {
        try await XcodeTestRunner(module: module, testBundle: testBundle).bootSimulator()
    }

    func provideScope(for test: Testing.Test, testCase: Testing.Test.Case?,
                      performing function: @concurrent @Sendable () async throws -> Void) async throws
    {
        let runner = XcodeTestRunner(module: module, testBundle: testBundle)
        try await runner.build()
        try await Self.$testRunner.withValue(runner, operation: function)
    }

    @TaskLocal static var testRunner: XcodeTestRunner?
}

extension Trait where Self == BuildProvider {
    static func build(_ type: String) -> Self {
        .init(module: "IntegrationTests-\(type)")
    }

    static func build(_ type: String, bundle: String) -> Self {
        .init(module: "IntegrationTests-\(type)", testBundle: "IntegrationTests-\(type)-\(bundle)")
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
