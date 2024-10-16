/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import EventsExporter

final class CacheManager {
    let cacheDir: Directory
    let commitDir: Directory?
    let sessionDir: Directory?
    let tempDir: Directory
    let debug: Bool
    
    init(environment: String, session: String, commit: String?, debug: Bool) throws {
        let name = Bundle.sdk.bundleIdentifier ?? "datadog"
        let cacheDir = try Directory.cache().createSubdirectory(path: name)
        let commitDir = try commit.map { try cacheDir.createSubdirectory(path: $0) }
        self.cacheDir = cacheDir
        self.commitDir = commitDir
        self.sessionDir = try commitDir.flatMap { try $0.createSubdirectory(path: session) }
        self.tempDir = try Directory.temporary()
            .createSubdirectory(path: "\(name)-\(UUID().uuidString)")
        self.debug = debug
    }
    
    func common(feature: String) throws -> Directory {
        try cacheDir.createSubdirectory(path: feature)
    }
    
    func commit(feature: String) throws -> Directory {
        guard let commit = commitDir else { throw InternalError(description: "commit dir is empty") }
        return try commit.createSubdirectory(path: feature)
    }
    
    func session(feature: String) throws -> Directory {
        guard let session = sessionDir else { throw InternalError(description: "session dir is empty") }
        return try session.createSubdirectory(path: feature)
    }
    
    func temp(feature: String) throws -> Directory {
        try tempDir.createSubdirectory(path: feature)
    }
    
    deinit {
        if !debug {
            try? tempDir.delete()
        } else {
            Log.debug("Temp directory left at: \(tempDir.url.path)")
        }
    }
}
