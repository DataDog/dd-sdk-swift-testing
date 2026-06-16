/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

extension FileManager {
    /// Walk directories matching `url` (which may contain `**` glob segments), calling `body` for
    /// each visited directory. Stops as soon as `body` returns `true`. `**` expansion is capped
    /// at `maxWildcardDepth` levels to avoid scanning huge directory trees.
    ///
    /// Unlike a pure pattern matcher, `body` is called on every directory encountered during `**`
    /// expansion — not only on leaves that match the full pattern — so callers can short-circuit
    /// as early as possible.
    @discardableResult
    func searchGlob(_ url: URL, maxWildcardDepth: Int = 3, body: (URL) -> Bool) -> Bool {
        let path = url.path
        guard path.contains("**") else {
            var isDir: ObjCBool = false
            guard fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }
            return body(url)
        }
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // Start walking from the longest concrete prefix before the first `**`.
        let staticCount = segments.prefix(while: { $0 != "**" }).count
        let staticPath = "/" + segments.prefix(staticCount).joined(separator: "/")
        let root = URL(fileURLWithPath: staticPath, isDirectory: true)
        let remaining = Array(segments.dropFirst(staticCount))
        return searchGlobSegments(prefix: root, segments: remaining, wildcardDepth: 0, maxWildcardDepth: maxWildcardDepth, body: body)
    }

    private func searchGlobSegments(prefix: URL, segments: [String], wildcardDepth: Int, maxWildcardDepth: Int, body: (URL) -> Bool) -> Bool {
        guard let head = segments.first else {
            var isDir: ObjCBool = false
            guard fileExists(atPath: prefix.path, isDirectory: &isDir), isDir.boolValue else { return false }
            return body(prefix)
        }
        let tail = Array(segments.dropFirst())
        if head == "**" {
            var isDir: ObjCBool = false
            guard fileExists(atPath: prefix.path, isDirectory: &isDir), isDir.boolValue else { return false }
            if tail.isEmpty {
                // `**` is the last segment: the current directory itself is a match.
                if body(prefix) { return true }
            } else {
                // `**` has a suffix pattern: only directories satisfying the tail are matches.
                // The current prefix is an anchor, not a result.
                if searchGlobSegments(prefix: prefix, segments: tail, wildcardDepth: wildcardDepth, maxWildcardDepth: maxWildcardDepth, body: body) { return true }
            }
            // One-or-more match: descend into subdirs, keeping `**` for further recursion.
            guard wildcardDepth < maxWildcardDepth else { return false }
            if let children = try? contentsOfDirectory(at: prefix,
                                                       includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsSubdirectoryDescendants]) {
                for child in children {
                    guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                    if searchGlobSegments(prefix: child, segments: segments, wildcardDepth: wildcardDepth + 1, maxWildcardDepth: maxWildcardDepth, body: body) { return true }
                }
            }
            return false
        }
        return searchGlobSegments(prefix: prefix.appendingPathComponent(head, isDirectory: true), segments: tail, wildcardDepth: wildcardDepth, maxWildcardDepth: maxWildcardDepth, body: body)
    }
}
