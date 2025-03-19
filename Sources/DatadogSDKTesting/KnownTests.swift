//
//  KnownTests.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 07/03/2025.
//

import Foundation
@_implementationOnly import EventsExporter

protocol KnownTestsService {
    var knownTests: KnownTests? { get }
    func start()
}

final class KnownTestsServiceImpl: KnownTestsService {
    let cacheFileName = "known_tests.json"
    
    private var _knownTests: KnownTestsMap? = nil {
        didSet {
            knownTests = _knownTests.map { KnownTests(tests: $0) }
        }
    }
    
    private(set) var knownTests: KnownTests? = nil
    
    var repository: String
    var service: String
    var environment: String
    var configurations: [String: String]
    var customConfigurations: [String: String]
    var cacheFolder: Directory
    var exporter: EventsExporterProtocol
    
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
    
    func start() {
        if cacheFolder.hasFile(named: cacheFileName) {
            // We have cached skippable tests. Try to load
            loadTestsFromDisk()
        }
        if _knownTests == nil {
            getTests()
            saveTestsToDisk()
        } else {
            Log.debug("Known tests loaded from disk")
        }
    }
    
    private func getTests() {
        _knownTests = exporter.knownTests(
            service: service, env: environment, repositoryURL: repository,
            configurations: configurations, customConfigurations: customConfigurations
        )
        // if we have empty array we will disable known tests functionality. All tests can't be new.
        if _knownTests?.count ?? 0 == 0 {
            _knownTests = nil
        }
        Log.debug("Known Tests: \(_knownTests.map {"\($0)"} ?? "nil")")
    }
    
    private func loadTestsFromDisk() {
        if let data = try? cacheFolder.file(named: cacheFileName).read(),
           let tests = try? JSONDecoder().decode(KnownTestsMap.self, from: data)
        {
            self._knownTests = tests
        }
        Log.debug("Loaded Known Tests: \(_knownTests.map { "\($0)" } ?? "nil")")
    }
    
    private func saveTestsToDisk() {
        if let tests = _knownTests, let data = try? JSONEncoder().encode(tests) {
            let testsFile = try? cacheFolder.createFile(named: cacheFileName)
            try? testsFile?.append(data: data)
        }
    }
}

final class KnownTests {
    let modules: [String: Module]
    let testCount: Int
    
    final class Module {
        let name: String
        let suites: [String: Suite]
        let testCount: Int
        
        init(name: String, suites: [String: [String]]) {
            let mapped = suites.map { (name, tests) in
                (name, Suite(name: name, tests: tests.asSet))
            }
            self.name = name
            self.suites = Dictionary(uniqueKeysWithValues: mapped)
            self.testCount = mapped.reduce(0) { $0 + $1.1.testCount }
        }
    }
    
    final class Suite {
        let name: String
        let tests: Set<String>
        
        var testCount: Int { tests.count }
        
        init(name: String, tests: Set<String>) {
            self.name = name
            self.tests = tests
        }
    }
    
    init(tests: KnownTestsMap) {
        let mapped = tests.map { (name, suites) in
            (name, Module(name: name, suites: suites))
        }
        self.modules = Dictionary(uniqueKeysWithValues: mapped)
        self.testCount = mapped.reduce(0) { $0 + $1.1.testCount }
    }
    
    func isKnown(test: String, in suite: String, and module: String) -> Bool {
        modules[module]?.suites[suite]?.tests.contains(test) ?? false
    }
    
    func isNew(test: String, in suite: String, and module: String) -> Bool {
        !isKnown(test: test, in: suite, and: module)
    }
}
