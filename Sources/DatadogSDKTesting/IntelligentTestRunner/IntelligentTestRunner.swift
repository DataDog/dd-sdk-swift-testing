/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@_implementationOnly import EventsExporter
import Foundation

class IntelligentTestRunner {
    private let itrCachePath = "itr"
    private let skippableFileName = "skippableTests"
    private var _skippableTests: SkipTests? = nil {
        didSet {
            skippableTests = _skippableTests.map { SkippableTests(tests: $0.tests) }
        }
    }

    var configurations: [String: String]
    var itrFolder: Directory?

    private(set) var skippableTests: SkippableTests? = nil
    var correlationId: String? { _skippableTests?.correlationId }

    init(configurations: [String: String]) {
        self.configurations = configurations
        itrFolder = try? DDTestMonitor.commitFolder?
            .subdirectory(path: itrCachePath)
            .subdirectory(path: DDTestMonitor.env.environment +
                String(configurations.stableHash) +
                String(DDTestMonitor.config.customConfigurations.stableHash))
    }

    func start() {
        if itrFolder != nil {
            // Previous commit folder exists, load from file
            Log.debug("Skippable tests loaded from disk")
            loadSkippableTestsFromDisk()

        } else {
            createITRFolder()
            getSkippableTests(repository: DDTestMonitor.env.git.repositoryURL)
            saveSkippableTestsToDisk()
        }
    }

    func getSkippableTests(repository: URL?) {
        guard let commit = DDTestMonitor.env.git.commitSHA, let url = repository else { return }
        _skippableTests = DDTestMonitor.tracer.eventsExporter?.skippableTests(
            repositoryURL: url.spanAttribute, sha: commit, testLevel: .test,
            configurations: configurations, customConfigurations: DDTestMonitor.config.customConfigurations
        )
        Log.debug("Skippable Tests: \(_skippableTests.map {"\($0)"} ?? "nil")")
    }

    private func createITRFolder() {
        itrFolder = try? DDTestMonitor.commitFolder?.createSubdirectory(path: itrCachePath)
            .createSubdirectory(path: DDTestMonitor.env.environment +
                String(configurations.stableHash) +
                String(DDTestMonitor.config.customConfigurations.stableHash))
    }

    private func loadSkippableTestsFromDisk() {
        if let skippableData = try? itrFolder?.file(named: skippableFileName).read(),
           let skippableTests = try? JSONDecoder().decode(SkipTests.self, from: skippableData)
        {
            _skippableTests = skippableTests
        }
        Log.debug("Skippable Tests: \(_skippableTests.map {"\($0)"} ?? "nil")")
    }

    private func saveSkippableTestsToDisk() {
        guard let itrFolder = itrFolder else {
            return
        }
        let skippableTestsFile = try? itrFolder.createFile(named: skippableFileName)
        
        if let tests = _skippableTests, let data = try? JSONEncoder().encode(tests) {
            try? skippableTestsFile?.append(data: data)
        }
    }
}

struct SkippableTests {
    struct Configuration {
        let standard: [String: String]?
        let custom: [String: String]?
    }
    
    struct Test {
        let name: String
        var configurations: [Configuration]
    }
    
    struct Suite {
        let name: String
        var methods: [String: Test]
        
        subscript(_ method: String) -> Test? { methods[method] }
    }
    
    let suites: [String: Suite]
    
    init(tests: [SkipTestPublicFormat]) {
        var suites = [String: Suite]()
        for test in tests {
            suites.get(key: test.suite, or: Suite(name: test.suite, methods: [:])) { suite in
                suite.methods.get(key: test.name, or: Test(name: test.name, configurations: [])) {
                    $0.configurations.append(Configuration(standard: test.configuration, custom: test.customConfiguration))
                }
            }
        }
        self.suites = suites
    }
    
    subscript(_ suite: String) -> Suite? { suites[suite] }
    
    subscript(_ suite: String, _ name: String) -> Test? { self[suite]?[name] }
}
