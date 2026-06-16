/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import Foundation
import XCTest

// Fixture tree (Tests/fixtures/glob/):
//
//   direct/                          ← plain directory, no wildcards
//   tree/
//     a/
//       _diag/
//     b/
//       _diag/
//     sub/
//       nested/
//         _diag/
//     deep/
//       l1/
//         l2/
//           l3/
//             l4/                    ← depth-4 child, beyond default maxWildcardDepth=3

internal class FileManagerExtensionsTests: XCTestCase {
    var globRoot: URL {
        Bundle(for: FileManagerExtensionsTests.self).resourceURL!
            .appendingPathComponent("fixtures/glob")
    }

    // MARK: - Exact path (no **)

    func testExactDirectory_existsCallsBodyOnce() {
        let url = globRoot.appendingPathComponent("direct")
        var visited: [String] = []
        let result = FileManager.default.searchGlob(url) { dir -> String? in
            visited.append(dir.lastPathComponent)
            return dir.lastPathComponent
        }
        XCTAssertEqual(result, "direct")
        XCTAssertEqual(visited, ["direct"])
    }

    func testExactDirectory_missingNeverCallsBody() {
        let url = globRoot.appendingPathComponent("nonexistent")
        var called = false
        let result = FileManager.default.searchGlob(url) { _ -> String? in
            called = true
            return "found"
        }
        XCTAssertNil(result)
        XCTAssertFalse(called)
    }

    func testExactDirectory_filePathNeverCallsBody() {
        // A file path (not a directory) should not be passed to body.
        let url = globRoot.appendingPathComponent("direct/dummy.txt")
        var called = false
        let result = FileManager.default.searchGlob(url) { _ -> String? in
            called = true
            return "found"
        }
        XCTAssertNil(result)
        XCTAssertFalse(called)
    }

    // MARK: - ** wildcard: pattern matching vs tree walk

    func testWildcard_withTailDoesNotCallBodyOnIntermediateDirs() {
        // When ** has a suffix (e.g. **/_diag), body is only called on directories that
        // satisfy the full pattern — not on intermediate traversal nodes.
        let url = globRoot.appendingPathComponent("tree/**/_diag")
        var visited = Set<String>()
        FileManager.default.searchGlob(url) { dir -> String? in
            visited.insert(dir.lastPathComponent)
            return nil  // keep visiting everything
        }
        XCTAssertFalse(visited.contains("a"),   "'a' is a traversal node, not a pattern match")
        XCTAssertFalse(visited.contains("b"),   "'b' is a traversal node, not a pattern match")
        XCTAssertFalse(visited.contains("sub"), "'sub' is a traversal node, not a pattern match")
        XCTAssertTrue(visited.contains("_diag"), "_diag dirs should be visited")
    }

    func testWildcard_withoutTailCallsBodyOnEveryDir() {
        // When ** is the last segment, body is called on every directory in the subtree.
        let url = globRoot.appendingPathComponent("tree/**")
        var visited = Set<String>()
        FileManager.default.searchGlob(url) { dir -> String? in
            visited.insert(dir.lastPathComponent)
            return nil
        }
        XCTAssertTrue(visited.contains("tree"),   "root of expansion should be visited")
        XCTAssertTrue(visited.contains("a"),      "subtree dirs should be visited")
        XCTAssertTrue(visited.contains("_diag"),  "_diag dirs should be visited")
        XCTAssertTrue(visited.contains("sub"),    "sub should be visited")
        XCTAssertTrue(visited.contains("nested"), "nested should be visited")
    }

    func testWildcard_findsLeafDiagDirsAtAllDepths() {
        // Each _diag dir should be visited exactly once with no double-calls.
        let url = globRoot.appendingPathComponent("tree/**/_diag")
        var diagParents: [String] = []
        FileManager.default.searchGlob(url) { dir -> String? in
            if dir.lastPathComponent == "_diag" {
                diagParents.append(dir.deletingLastPathComponent().lastPathComponent)
            }
            return nil
        }
        XCTAssertEqual(diagParents.count, 3, "exactly three _diag dirs, each visited once")
        XCTAssertTrue(diagParents.contains("a"))
        XCTAssertTrue(diagParents.contains("b"))
        XCTAssertTrue(diagParents.contains("nested"))
    }

    // MARK: - ** wildcard: early exit and return value

    func testWildcard_returnsFirstNonNilValue() {
        let url = globRoot.appendingPathComponent("tree/**")
        var count = 0
        let result = FileManager.default.searchGlob(url) { dir -> String? in
            count += 1
            return dir.lastPathComponent  // stop on first dir
        }
        XCTAssertNotNil(result)
        XCTAssertEqual(count, 1, "body should be called exactly once before stopping")
    }

    func testWildcard_returnsNilWhenNothingMatches() {
        let url = globRoot.appendingPathComponent("tree/**/_diag")
        let result = FileManager.default.searchGlob(url) { _ -> String? in nil }
        XCTAssertNil(result)
    }

    func testWildcard_returnsCorrectValue() {
        // Verify the returned value is what body produced, not just a sentinel.
        let url = globRoot.appendingPathComponent("tree/**/_diag")
        let result = FileManager.default.searchGlob(url) { dir -> URL? in
            dir.lastPathComponent == "_diag" ? dir : nil
        }
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lastPathComponent, "_diag")
    }

    // MARK: - ** wildcard: depth limit

    func testWildcard_defaultDepthLimitExcludesDeepDirs() {
        // l4 is at depth 4 under tree/deep — beyond the default maxWildcardDepth of 3.
        let url = globRoot.appendingPathComponent("tree/deep/**")
        var visited = Set<String>()
        FileManager.default.searchGlob(url) { dir -> String? in
            visited.insert(dir.lastPathComponent)
            return nil
        }
        XCTAssertTrue(visited.contains("l1"))
        XCTAssertTrue(visited.contains("l2"))
        XCTAssertTrue(visited.contains("l3"))
        XCTAssertFalse(visited.contains("l4"), "l4 is at depth 4, should be excluded by maxWildcardDepth=3")
    }

    func testWildcard_customDepthLimitRespected() {
        let url = globRoot.appendingPathComponent("tree/deep/**")
        var visited = Set<String>()
        FileManager.default.searchGlob(url, maxWildcardDepth: 1) { dir -> String? in
            visited.insert(dir.lastPathComponent)
            return nil
        }
        XCTAssertTrue(visited.contains("deep"), "root of ** expansion should be visited")
        XCTAssertTrue(visited.contains("l1"),   "depth-1 child should be visited")
        XCTAssertFalse(visited.contains("l2"),  "depth-2 child should be excluded at maxWildcardDepth=1")
    }

    // MARK: - Concrete root before **

    func testWildcard_usesConcreteRootBeforeWildcard() {
        // Pattern rooted at tree/a — only subtree of a should be visited.
        let url = globRoot.appendingPathComponent("tree/a/**")
        var visited = Set<String>()
        FileManager.default.searchGlob(url) { dir -> String? in
            visited.insert(dir.lastPathComponent)
            return nil
        }
        XCTAssertTrue(visited.contains("a"))
        XCTAssertTrue(visited.contains("_diag"))
        XCTAssertFalse(visited.contains("b"),   "b is outside the root, should not be visited")
        XCTAssertFalse(visited.contains("sub"), "sub is outside the root, should not be visited")
    }

    func testWildcard_nonexistentRootNeverCallsBody() {
        let url = globRoot.appendingPathComponent("nonexistent/**/_diag")
        var called = false
        let result = FileManager.default.searchGlob(url) { _ -> String? in
            called = true
            return "found"
        }
        XCTAssertNil(result)
        XCTAssertFalse(called)
    }
}
