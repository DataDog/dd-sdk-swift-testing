/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import EventsExporter

final class CacheManager {
    let cacheDir: Directory
    let commitDir: Directory
    let sessionDir: Directory
    let tempDir: Directory
    let debug: Bool
    
    init(session: String, commit: String, debug: Bool) throws {
        let name = Bundle.sdk.bundleIdentifier ?? "datadog"
        let cacheDir = try Directory.cache().createSubdirectory(path: name)
        let commitDir = try cacheDir.createSubdirectory(path: commit)
        self.cacheDir = cacheDir
        self.commitDir = commitDir
        self.sessionDir = try commitDir.createSubdirectory(path: session)
        self.tempDir = try Directory.temporary()
            .createSubdirectory(path: "\(name)-\(UUID().uuidString)")
        self.debug = debug
        if debug {
            Log.debug("Session Directory: \(sessionDir.url.absoluteString)")
            Log.debug("Temp Directory: \(tempDir.url.absoluteString)")
        }
    }
    
    func common(feature: String) throws -> Directory {
        try cacheDir.createSubdirectory(path: feature)
    }
    
    func commit(feature: String) throws -> Directory {
        try commitDir.createSubdirectory(path: feature)
    }
    
    func session(feature: String) throws -> Directory {
        try sessionDir.createSubdirectory(path: feature)
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
