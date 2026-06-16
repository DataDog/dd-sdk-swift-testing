/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

extension FileManager {
    /// Walk directories matching `url` (which may contain `**` glob segments), calling `body` for
    /// each matched directory. Returns the first non-`nil` value produced by `body`, or `nil` if
    /// no directory matched. `**` expansion is capped at `maxWildcardDepth` levels to avoid
    /// scanning huge directory trees.
    ///
    /// - `body` returns `nil`  → keep searching
    /// - `body` returns a value → stop immediately and return that value
    ///
    /// When `**` has a suffix pattern (e.g. `**/_diag`), `body` is called only on directories
    /// that satisfy the full subpath. When `**` is the last segment, `body` is called on every
    /// directory in the subtree.
    @discardableResult
    func searchGlob<T>(_ url: URL, maxWildcardDepth: Int = 3, body: (URL) -> T?) -> T? {
        let path = url.path
        guard path.contains("**") else {
            var isDir: ObjCBool = false
            guard fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return body(url)
        }
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let staticCount = segments.prefix(while: { $0 != "**" }).count
        let staticPath = "/" + segments.prefix(staticCount).joined(separator: "/")
        let root = URL(fileURLWithPath: staticPath, isDirectory: true)
        let remaining = Array(segments.dropFirst(staticCount))
        return searchGlobSegments(prefix: root, segments: remaining, wildcardDepth: 0, maxWildcardDepth: maxWildcardDepth, body: body)
    }

    private func searchGlobSegments<T>(prefix: URL, segments: [String], wildcardDepth: Int, maxWildcardDepth: Int, body: (URL) -> T?) -> T? {
        guard let head = segments.first else {
            var isDir: ObjCBool = false
            guard fileExists(atPath: prefix.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return body(prefix)
        }
        let tail = Array(segments.dropFirst())
        if head == "**" {
            var isDir: ObjCBool = false
            guard fileExists(atPath: prefix.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            if tail.isEmpty {
                // `**` is the last segment: the current directory itself is a match.
                if let result = body(prefix) { return result }
            } else {
                // `**` has a suffix pattern: only directories satisfying the tail are matches.
                // The current prefix is an anchor, not a result.
                if let result = searchGlobSegments(prefix: prefix, segments: tail, wildcardDepth: wildcardDepth, maxWildcardDepth: maxWildcardDepth, body: body) { return result }
            }
            // One-or-more match: descend into subdirs, keeping `**` for further recursion.
            guard wildcardDepth < maxWildcardDepth else { return nil }
            if let children = try? contentsOfDirectory(at: prefix,
                                                       includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsSubdirectoryDescendants]) {
                for child in children {
                    guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                    if let result = searchGlobSegments(prefix: child, segments: segments, wildcardDepth: wildcardDepth + 1, maxWildcardDepth: maxWildcardDepth, body: body) { return result }
                }
            }
            return nil
        }
        return searchGlobSegments(prefix: prefix.appendingPathComponent(head, isDirectory: true), segments: tail, wildcardDepth: wildcardDepth, maxWildcardDepth: maxWildcardDepth, body: body)
    }
}
