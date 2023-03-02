/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class CodeOwnersGithubTests: XCTestCase {
    let codeOwnersGitHubSample = """
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

    func testCodeOwnersIsCorrectlyInitialized() {
        let codeOwners = CodeOwners(content: codeOwnersGitHubSample)
        XCTAssertEqual(codeOwners.section.count, 1)
        XCTAssertEqual(codeOwners.section.first?.key, "[empty]")
        XCTAssertEqual(codeOwners.section.first?.value.count, 7)
    }

    func testIfPathNotFoundDefaultIsReturned() {
        let codeOwners = CodeOwners(content: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("unexistent/path/test.swift")
        XCTAssertEqual(defaultOwner, #"["@global-owner1","@global-owner2"]"#)
    }

    func testIfPathIsFoundReturnOwner() {
        let codeOwners = CodeOwners(content: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("apps/test.swift")
        XCTAssertEqual(defaultOwner, #"["@octocat"]"#)
    }

    func testIfPathIsFound2ReturnOwner() {
        let codeOwners = CodeOwners(content: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("/example/apps/test.swift")
        XCTAssertEqual(defaultOwner, #"["@octocat"]"#)
    }

    func testIfPathIsFoundAtRootReturnOwner() {
        let codeOwners = CodeOwners(content: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("/docs/test.swift")
        XCTAssertEqual(defaultOwner, #"["@doctocat"]"#)
    }

    func testIfPathIsNotFoundAtRootReturnNextMatch() {
        let codeOwners = CodeOwners(content: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("/examples/docs/test.swift")
        XCTAssertEqual(defaultOwner, #"["docs@example.com"]"#)
    }

    func testIfPathIsNotFoundReturnGlobal() {
        let codeOwners = CodeOwners(content: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("/examples/docs/inside/test.swift")
        XCTAssertEqual(defaultOwner, #"["@global-owner1","@global-owner2"]"#)
    }

    func testExtensionValue() {
        let codeOwners = CodeOwners(content: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("/component/path/test.js")
        XCTAssertEqual(defaultOwner, #"["@js-owner"]"#)
    }
}

class CodeOwnersGitlabTests: XCTestCase {
    let codeOwnersGitLabSample = ##"""
    # This is an example of a CODEOWNERS file.
    # Lines that start with `#` are ignored.

    # app/ @commented-rule

    # Specify a default Code Owner by using a wildcard:
    * @default-codeowner

    # Specify multiple Code Owners by using a tab or space:
    * @multiple @code @owners

    # Rules defined later in the file take precedence over the rules
    # defined before.
    # For example, for all files with a filename ending in `.rb`:
    *.rb @ruby-owner

    # Files with a `#` can still be accessed by escaping the pound sign:
    \#file_with_pound.rb @owner-file-with-pound

    # Specify multiple Code Owners separated by spaces or tabs.
    # In the following case the CODEOWNERS file from the root of the repo
    # has 3 Code Owners (@multiple @code @owners):
    CODEOWNERS @multiple @code @owners

    # You can use both usernames or email addresses to match
    # users. Everything else is ignored. For example, this code
    # specifies the `@legal` and a user with email `janedoe@gitlab.com` as the
    # owner for the LICENSE file:
    LICENSE @legal this_does_not_match janedoe@gitlab.com

    # Use group names to match groups, and nested groups to specify
    # them as owners for a file:
    README @group @group/with-nested/subgroup

    # End a path in a `/` to specify the Code Owners for every file
    # nested in that directory, on any level:
    /docs/ @all-docs

    # End a path in `/*` to specify Code Owners for every file in
    # a directory, but not nested deeper. This code matches
    # `docs/index.md` but not `docs/projects/index.md`:
    /docs/* @root-docs

    # This code makes matches a `lib` directory nested anywhere in the repository:
    lib/ @lib-owner

    # This code match only a `config` directory in the root of the repository:
    /config/ @config-owner

    # If the path contains spaces, escape them like this:
    path\ with\ spaces/ @space-owner

    # Code Owners section:
    [Documentation]
    ee/docs    @docs
    docs       @docs

    [Database]
    README.md  @database
    model/db   @database

    # This section is combined with the previously defined [Documentation] section:
    [DOCUMENTATION]
    README.md  @docs
    """##

    func testCodeOwnersIsCorrectlyInitialized() {
        let codeOwners = CodeOwners(content: codeOwnersGitLabSample)
        XCTAssertEqual(codeOwners.section.count, 3)
    }

    func testCodeOwnersGitlab1() throws {
        let codeOwners = CodeOwners(content: codeOwnersGitLabSample)
        let possibleOwner = codeOwners.ownersForPath("apps/README.md")
        let defaultOwner = try XCTUnwrap(possibleOwner)
        XCTAssertTrue(defaultOwner.contains("\"@docs\""))
        XCTAssertTrue(defaultOwner.contains("\"@database\""))
        XCTAssertTrue(defaultOwner.contains("\"@multiple\""))
        XCTAssertTrue(defaultOwner.contains("\"@code\""))
        XCTAssertTrue(defaultOwner.contains("\"@owners\""))
    }

    func testCodeOwnersGitlab2() throws{
        let codeOwners = CodeOwners(content: codeOwnersGitLabSample)
        let possibleOwner = codeOwners.ownersForPath("model/db")
        let defaultOwner = try XCTUnwrap(possibleOwner)
        XCTAssertTrue(defaultOwner.contains("\"@database\""))
        XCTAssertTrue(defaultOwner.contains("\"@multiple\""))
        XCTAssertTrue(defaultOwner.contains("\"@code\""))
        XCTAssertTrue(defaultOwner.contains("\"@owners\""))
    }

    func testCodeOwnersGitlab3() {
        let codeOwners = CodeOwners(content: codeOwnersGitLabSample)
        let defaultOwner = codeOwners.ownersForPath("/config/data.conf")
        XCTAssertEqual(defaultOwner, "[\"@config-owner\"]")
    }

    func testCodeOwnersGitlab4() {
        let codeOwners = CodeOwners(content: codeOwnersGitLabSample)
        let defaultOwner = codeOwners.ownersForPath("/docs/root.md")
        XCTAssertEqual(defaultOwner, "[\"@root-docs\"]")
    }

    func testCodeOwnersGitlab5() {
        let codeOwners = CodeOwners(content: codeOwnersGitLabSample)
        let defaultOwner = codeOwners.ownersForPath("/docs/sub/root.md")
        XCTAssertEqual(defaultOwner, "[\"@all-docs\"]")
    }

    func testCodeOwnersGitlab6() throws {
        let codeOwners = CodeOwners(content: codeOwnersGitLabSample)
        let possibleOwner = codeOwners.ownersForPath("/src/README")
        let defaultOwner = try XCTUnwrap(possibleOwner)
        XCTAssertTrue(defaultOwner.contains("\"@group\""))
        XCTAssertTrue(defaultOwner.contains("\"@group/with-nested/subgroup\""))
    }

    func testCodeOwnersGitlab7() {
        let codeOwners = CodeOwners(content: codeOwnersGitLabSample)
        let defaultOwner = codeOwners.ownersForPath("/src/lib/internal.h")
        XCTAssertEqual(defaultOwner, "[\"@lib-owner\"]")
    }

    func testCodeOwnersGitlab8() throws {
        let codeOwners = CodeOwners(content: codeOwnersGitLabSample)
        let possibleOwner = codeOwners.ownersForPath("src/ee/docs")
        let defaultOwner = try XCTUnwrap(possibleOwner)
        XCTAssertTrue(defaultOwner.contains("\"@docs\""))
        XCTAssertTrue(defaultOwner.contains("\"@multiple\""))
        XCTAssertTrue(defaultOwner.contains("\"@code\""))
        XCTAssertTrue(defaultOwner.contains("\"@owners\""))
    }
}
