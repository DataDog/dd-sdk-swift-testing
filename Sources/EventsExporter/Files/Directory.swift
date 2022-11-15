/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

/// An abstraction over file system directory where SDK stores its files.
 public struct Directory {
    let url: URL

    /// Creates subdirectory with given path under system caches directory.
     public init(withSubdirectoryPath path: String) throws {
        self.init(url: try createCachesSubdirectoryIfNotExists(subdirectoryPath: path))
    }

     public init(url: URL) {
        self.url = url
    }

    /// Creates file with given name.
     public func createFile(named fileName: String) throws -> File {
        let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) == true else {
            throw ExporterError(description: "Cannot create file at path: \(fileURL.path)")
        }
        return File(url: fileURL)
    }

    /// Returns file with given name.
     public func file(named fileName: String) -> File? {
        let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return File(url: fileURL)
        } else {
            return nil
        }
    }

    /// Returns all files of this directory.
     public func files() throws -> [File] {
        return try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .canonicalPathKey])
            .map { url in File(url: url) }
    }

     public func getURL() -> URL {
         return url
     }
     
     /// Deletes all files in this directory.
     public func deleteDirectory() throws {
         if FileManager.default.fileExists(atPath: url.path) {
             try FileManager.default.removeItem(at: url)
         }
     }
}

/// Creates subdirectory at given path in `/Library/Caches` if it does not exist. Might throw `ExporterError` when it's not possible.
/// * `/Library/Caches` is exclduded from iTunes and iCloud backups by default.
/// * System may delete data in `/Library/Cache` to free up disk space which reduces the impact on devices working under heavy space pressure.
private func createCachesSubdirectoryIfNotExists(subdirectoryPath: String) throws -> URL {
    guard let cachesDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        throw ExporterError(description: "Cannot obtain `/Library/Caches/` url.")
    }
    let subdirectoryURL = cachesDirectoryURL.appendingPathComponent(subdirectoryPath, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: subdirectoryURL, withIntermediateDirectories: true, attributes: nil)
    } catch {
        throw ExporterError(description: "Cannot create subdirectory in `/Library/Caches/` folder.")
    }
    return subdirectoryURL
}
