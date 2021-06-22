/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest


class CodeOwnersTests: XCTestCase {
    
    func testCodeOwnersIsCorrectlyInitialized() {
        let codeOwners = CodeOwners(content: codeOwnersSample)
        XCTAssertEqual(codeOwners.ownerEntries.count, 7)
    }

    func testIfPathNotFoundDefaultIsReturned() {
        let codeOwners = CodeOwners(content: codeOwnersSample)
        let defaultOwner = codeOwners.ownersForPath("unexistent/path/test.swift")
        XCTAssertEqual(defaultOwner, #"["@global-owner1","@global-owner2"]"#)
    }

    func testIfPathIsFoundReturnOwner() {
        let codeOwners = CodeOwners(content: codeOwnersSample)
        let defaultOwner = codeOwners.ownersForPath("apps/test.swift")
        XCTAssertEqual(defaultOwner, #"["@octocat"]"#)
    }

    func testIfPathIsFound2ReturnOwner() {
        let codeOwners = CodeOwners(content: codeOwnersSample)
        let defaultOwner = codeOwners.ownersForPath("/example/apps/test.swift")
        XCTAssertEqual(defaultOwner, #"["@octocat"]"#)
    }

    func testIfPathIsFoundAtRootReturnOwner() {
        let codeOwners = CodeOwners(content: codeOwnersSample)
        let defaultOwner = codeOwners.ownersForPath("/docs/test.swift")
        XCTAssertEqual(defaultOwner, #"["@doctocat"]"#)
    }

    func testIfPathIsNotFoundAtRootReturnNextMatch() {
        let codeOwners = CodeOwners(content: codeOwnersSample)
        let defaultOwner = codeOwners.ownersForPath("/examples/docs/test.swift")
        XCTAssertEqual(defaultOwner, #"["docs@example.com"]"#)
    }

    func testIfPathIsNotFoundReturnGlobal() {
        let codeOwners = CodeOwners(content: codeOwnersSample)
        let defaultOwner = codeOwners.ownersForPath("/examples/docs/inside/test.swift")
        XCTAssertEqual(defaultOwner, #"["@global-owner1","@global-owner2"]"#)
    }

    func testExtensionValue() {
        let codeOwners = CodeOwners(content: codeOwnersSample)
        let defaultOwner = codeOwners.ownersForPath("/component/path/test.js")
        XCTAssertEqual(defaultOwner, #"["@js-owner"]"#)
    }
}


let codeOwnersSample = """
# This is a comment.
# Each line is a file pattern followed by one or more owners.

# These owners will be the default owners for everything in
# the repo. Unless a later match takes precedence,
# @global-owner1 and @global-owner2 will be requested for
# review when someone opens a pull request.
*       @global-owner1 @global-owner2

# Order is important; the last matching pattern takes the most
# precedence. When someone opens a pull request that only
# modifies JS files, only @js-owner and not the global
# owner(s) will be requested for a review.
*.js    @js-owner

# You can also use email addresses if you prefer. They'll be
# used to look up users just like we do for commit author
# emails.
*.go docs@example.com

# In this example, @doctocat owns any files in the build/logs
# directory at the root of the repository and any of its
# subdirectories.
/build/logs/ @doctocat

# The `docs/*` pattern will match files like
# `docs/getting-started.md` but not further nested files like
# `docs/build-app/troubleshooting.md`.
docs/*  docs@example.com

# In this example, @octocat owns any file in an apps directory
# anywhere in your repository.
apps/ @octocat

# In this example, @doctocat owns any file in the `/docs`
# directory in the root of your repository and any of its
# subdirectories.
/docs/ @doctocat
"""

