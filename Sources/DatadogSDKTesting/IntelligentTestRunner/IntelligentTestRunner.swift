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
            skippableTests.removeAll()
            guard let newTests = _skippableTests else { return }
            for test in newTests.tests {
                skippableTests.get(key: test.suite, or: [:]) { methods in
                    methods.get(key: test.name, or: []) { $0.append(test) }
                }
            }
        }
    }

    var configurations: [String: String]
    var itrFolder: Directory?

    // [suite: [name: [info]]]
    private(set) var skippableTests: [String: [String: [SkipTestPublicFormat]]]
    var skippableTestsList: [SkipTestPublicFormat] { _skippableTests?.tests ?? [] }
    
    var correlationId: String? { _skippableTests?.correlationId }

    init(configurations: [String: String]) {
        self.configurations = configurations
        skippableTests = [:]
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
