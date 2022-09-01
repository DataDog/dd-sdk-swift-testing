/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@_implementationOnly import EventsExporter
import Foundation

class IntelligentTestRunner {
    var configurations: [String: String]
    var skippableTests: [SkipTestPublicFormat] = []

    init(configurations: [String: String]) {
        self.configurations = configurations
    }

    func start() {
        getSkippableTests(repository: getRepositoryURL())
    }

    func getSkippableTests(repository: String) {
        guard let commit = DDTestMonitor.env.commit else { return }

        skippableTests = DDTestMonitor.tracer.eventsExporter?.skippableTests(repositoryURL: getRepositoryURL(), sha: commit, configurations: configurations) ?? []
        Log.debug("Skippable Tests: \(skippableTests)")
    }

    private func getRepositoryURL() -> String {
        let url = Spawn.commandWithResult(#"git -C "\#(DDTestMonitor.env.workspacePath!)" config --get remote.origin.url"#).trimmingCharacters(in: .whitespacesAndNewlines)
        return url
    }
}
