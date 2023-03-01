/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@_implementationOnly import EventsExporter
import Foundation

class IntelligentTestRunner {
    private let itrCachePath = "itr"
    private let skippableFileName = "skippableTests"

    var configurations: [String: String]
    var skippableTests: [SkipTestPublicFormat] = []
    var itrFolder: Directory?

    init(configurations: [String: String]) {
        self.configurations = configurations
        itrFolder = try? DDTestMonitor.commitFolder?
            .subdirectory(path: itrCachePath)
            .subdirectory(path: DDTestMonitor.env.getDatadogEnvValue() +
                String(configurations.stableHash) +
                String(DDTestMonitor.env.customConfigurations.stableHash))
    }

    func start() {
        if itrFolder != nil {
            // Previous commit folder exists, load from file
            Log.debug("Skippable tests loaded from disk")
            loadSkippableTestsFromDisk()

        } else {
            createITRFolder()
            getSkippableTests(repository: DDTestMonitor.localRepositoryURLPath)
            saveSkippableTestsToDisk()
        }
    }

    func getSkippableTests(repository: String) {
        guard let commit = DDTestMonitor.env.commit else { return }
        skippableTests = DDTestMonitor.tracer.eventsExporter?.skippableTests(repositoryURL: repository, sha: commit, configurations: configurations, customConfigurations: DDTestMonitor.env.customConfigurations) ?? []
        Log.debug("Skippable Tests: \(skippableTests)")
    }

    private func createITRFolder() {
        itrFolder = try? DDTestMonitor.commitFolder?.createSubdirectory(path: itrCachePath)
            .createSubdirectory(path: DDTestMonitor.env.getDatadogEnvValue() +
                String(configurations.stableHash) +
                String(DDTestMonitor.env.customConfigurations.stableHash))
    }

    private func loadSkippableTestsFromDisk() {
        if let skippableData = try? itrFolder?.file(named: skippableFileName).read(),
           let skippableTests = try? JSONDecoder().decode([SkipTestPublicFormat].self, from: skippableData)
        {
            self.skippableTests = skippableTests
        }
        Log.debug("Skippable Tests: \(skippableTests)")
    }

    private func saveSkippableTestsToDisk() {
        guard let itrFolder = itrFolder else {
            return
        }
        let skippableTestsFile = try? itrFolder.createFile(named: skippableFileName)

        if let skippableData = try? JSONEncoder().encode(skippableTests) {
            try? skippableTestsFile?.append(data: skippableData)
        }
    }
}
