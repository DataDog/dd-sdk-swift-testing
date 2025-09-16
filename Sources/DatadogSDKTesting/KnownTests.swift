/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final class KnownTests: TestHooksFeature {
    static var id: String = "Known Tests"
    
    let modules: [String: Module]
    
    init(tests: KnownTestsMap) {
        let mapped = tests.map { (name, suites) in
            (name, Module(name: name, suites: suites))
        }
        self.modules = Dictionary(uniqueKeysWithValues: mapped)
    }
    
    func isKnown(test: String, in suite: String, and module: String) -> Bool {
        modules[module]?.suites[suite]?.tests.contains(test) ?? false
    }
    
    func isNew(test: String, in suite: String, and module: String) -> Bool {
        !isKnown(test: test, in: suite, and: module)
    }
    
    func isNew(test: any TestRun) -> Bool {
        isNew(test: test.name, in: test.suite.name, and: test.module.name)
    }
    
    func testWillStart(test: any TestRun, info: TestRunInfoStart) {
        // Mark new tests
        if isNew(test: test) {
            test.set(tag: DDTestTags.testIsNew, value: "true")
        }
    }
    
    func stop() {}
}

extension KnownTests {
    struct Module {
        let name: String
        let suites: [String: Suite]
        
        init(name: String, suites: [String: [String]]) {
            let mapped = suites.map { (name, tests) in
                (name, Suite(name: name, tests: tests))
            }
            self.name = name
            self.suites = Dictionary(uniqueKeysWithValues: mapped)
        }
    }
    
    struct Suite {
        let name: String
        let tests: Set<String>

        init(name: String, tests: [String]) {
            self.name = name
            self.tests = Set(tests)
        }
    }
}

struct KnownTestsFactory: FeatureFactory {
    typealias FT = KnownTests
    
    let repository: String
    let service: String
    let environment: String
    let configurations: [String: String]
    let customConfigurations: [String: String]
    let cacheFolder: Directory
    let exporter: EventsExporterProtocol
    let cacheFileName = "known_tests.json"
    
    init(repository: String, service: String, environment: String,
         configurations: [String: String], custom: [String: String],
         exporter: EventsExporterProtocol, cache: Directory
    ) {
        self.configurations = configurations
        self.customConfigurations = custom
        self.cacheFolder = cache
        self.repository = repository
        self.service = service
        self.environment = environment
        self.exporter = exporter
    }
    
    static func isEnabled(config: Config, env: Environment, remote: TracerSettings) -> Bool {
        remote.knownTestsEnabled
    }
    
    func create(log: Logger) -> KnownTests? {
        if let tests = loadTestsFromDisk(log: log) {
            log.debug("Known Tests Enabled")
            return KnownTests(tests: tests)
        }
        guard let tests = getTests(exporter: exporter, log: log) else {
            return nil
        }
        saveTests(tests: tests)
        log.debug("Known Tests Enabled")
        return KnownTests(tests: tests)
    }
    
    private func loadTestsFromDisk(log: Logger) -> KnownTestsMap? {
        guard cacheFolder.hasFile(named: cacheFileName) else { return nil }
        guard let data = try? cacheFolder.file(named: cacheFileName).read() else {
            log.print("Known Tests: Can't read \(cacheFileName) from \(cacheFolder)")
            return nil
        }
        do {
            let tests = try JSONDecoder().decode(KnownTestsMap.self, from: data)
            log.debug("Known Tests: loaded tests: \(tests)")
            return tests
        } catch {
            log.print("Known Tests: Can't decode tests data: \(error)")
            return nil
        }
    }
    
    private func getTests(exporter: EventsExporterProtocol, log: Logger) -> KnownTestsMap? {
        let tests = exporter.knownTests(
            service: service, env: environment, repositoryURL: repository,
            configurations: configurations, customConfigurations: customConfigurations
        )
        guard let tests = tests else {
            Log.print("Known Tests: tests request failed")
            return nil
        }
        Log.debug("Known Tests: tests: \(tests)")
        // if we have empty array we should disable Known Tests functionality
        guard tests.count > 0 else { return nil }
        return tests
    }
    
    private func saveTests(tests: KnownTestsMap) {
        if let data = try? JSONEncoder().encode(tests) {
            let testsFile = try? cacheFolder.createFile(named: cacheFileName)
            try? testsFile?.append(data: data)
        }
    }
}
