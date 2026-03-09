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

    func testCodeOwnersIsCorrectlyInitialized() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitHubSample)
        XCTAssertEqual(codeOwners.sections.count, 1)
        XCTAssertEqual(codeOwners.sections.first?.name, "[]")
        XCTAssertEqual(codeOwners.sections.first?.entries.count, 7)
    }

    func testIfPathNotFoundDefaultIsReturned() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("unexistent/path/test.swift")
        XCTAssertEqual(defaultOwner, #"["@global-owner1","@global-owner2"]"#)
    }

    func testIfPathIsFoundReturnOwner() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("apps/test.swift")
        XCTAssertEqual(defaultOwner, #"["@octocat"]"#)
    }

    func testIfPathIsFound2ReturnOwner() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("/example/apps/test.swift")
        XCTAssertEqual(defaultOwner, #"["@octocat"]"#)
    }

    func testIfPathIsFoundAtRootReturnOwner() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("/docs/test.swift")
        XCTAssertEqual(defaultOwner, #"["@doctocat"]"#)
    }
    
    func testIfPathIsFoundAtRootWithoutSlashReturnOwner() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("docs/test.swift")
        XCTAssertEqual(defaultOwner, #"["@doctocat"]"#)
    }

    func testIfPathIsNotFoundAtRootReturnNextMatch() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("/examples/docs/test.swift")
        XCTAssertEqual(defaultOwner, #"["docs@example.com"]"#)
    }

    func testIfPathIsNotFoundReturnGlobal() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitHubSample)
        let defaultOwner = codeOwners.ownersForPath("/examples/docs/inside/test.swift")
        XCTAssertEqual(defaultOwner, #"["@global-owner1","@global-owner2"]"#)
    }

    func testExtensionValue() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitHubSample)
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

    func testCodeOwnersIsCorrectlyInitialized() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        XCTAssertEqual(codeOwners.sections.count, 3)
    }

    func testCodeOwnersGitlab1() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        let possibleOwner = codeOwners.ownersForPath("apps/README.md")
        let defaultOwner = try XCTUnwrap(possibleOwner)
        XCTAssertTrue(defaultOwner.contains("\"@docs\""))
        XCTAssertTrue(defaultOwner.contains("\"@database\""))
        XCTAssertTrue(defaultOwner.contains("\"@multiple\""))
        XCTAssertTrue(defaultOwner.contains("\"@code\""))
        XCTAssertTrue(defaultOwner.contains("\"@owners\""))
    }

    func testCodeOwnersGitlab2() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        let possibleOwner = codeOwners.ownersForPath("model/db")
        let defaultOwner = try XCTUnwrap(possibleOwner)
        XCTAssertTrue(defaultOwner.contains("\"@database\""))
        XCTAssertTrue(defaultOwner.contains("\"@multiple\""))
        XCTAssertTrue(defaultOwner.contains("\"@code\""))
        XCTAssertTrue(defaultOwner.contains("\"@owners\""))
    }

    func testCodeOwnersGitlab3() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        let defaultOwner = codeOwners.ownersForPath("/config/data.conf")
        XCTAssertEqual(defaultOwner, "[\"@config-owner\"]")
    }

    func testCodeOwnersGitlab4() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        let defaultOwner = codeOwners.ownersForPath("/docs/root.md")
        XCTAssertEqual(defaultOwner, "[\"@root-docs\",\"@docs\"]")
    }

    func testCodeOwnersGitlab5() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        let defaultOwner = codeOwners.ownersForPath("/docs/sub/root.md")
        XCTAssertEqual(defaultOwner, "[\"@all-docs\",\"@docs\"]")
    }

    func testCodeOwnersGitlab6() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        let possibleOwner = codeOwners.ownersForPath("/src/README")
        let defaultOwner = try XCTUnwrap(possibleOwner)
        XCTAssertTrue(defaultOwner.contains("\"@group\""))
        XCTAssertTrue(defaultOwner.contains("\"@group/with-nested/subgroup\""))
    }

    func testCodeOwnersGitlab7() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        let defaultOwner = codeOwners.ownersForPath("/src/lib/internal.h")
        XCTAssertEqual(defaultOwner, "[\"@lib-owner\"]")
    }

    func testCodeOwnersGitlab8() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        let possibleOwner = codeOwners.ownersForPath("src/ee/docs")
        let defaultOwner = try XCTUnwrap(possibleOwner)
        XCTAssertTrue(defaultOwner.contains("\"@docs\""))
        XCTAssertTrue(defaultOwner.contains("\"@multiple\""))
        XCTAssertTrue(defaultOwner.contains("\"@code\""))
        XCTAssertTrue(defaultOwner.contains("\"@owners\""))
    }
    
    func testCodeOwnersGitlab9() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        let defaultOwner = codeOwners.ownersForPath("config/data.conf")
        XCTAssertEqual(defaultOwner, "[\"@config-owner\"]")
    }
    
    func testCodeOwnersFileWithPund() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersGitLabSample)
        let defaultOwner = codeOwners.ownersForPath("#file_with_pound.rb")
        XCTAssertEqual(defaultOwner, "[\"@owner-file-with-pound\"]")
    }
}

class CodeOwnersEdgeCases: XCTestCase {
    let codeOwnersEdgeCases = ##"""
    a @owner1
    b @owner2
    """##

    func testCodeOwnersIsCorrectlyInitialized() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersEdgeCases)
        XCTAssertEqual(codeOwners.sections.count, 1)
        XCTAssertEqual(codeOwners.sections.first?.entries.count, 2)
    }

    func testCodeOwnersOneFile() throws {
        let codeOwners = try CodeOwners(parsing: codeOwnersEdgeCases)
        let possibleOwner = codeOwners.ownersForPath("a")
        let defaultOwner = try XCTUnwrap(possibleOwner)
        XCTAssertTrue(defaultOwner.contains("\"@owner1\""))
        
        let possibleOwner2 = codeOwners.ownersForPath("aa")
        XCTAssertNil(possibleOwner2)
        
        let possibleOwner3 = codeOwners.ownersForPath("b")
        let defaultOwner3 = try XCTUnwrap(possibleOwner3)
        XCTAssertTrue(defaultOwner3.contains("\"@owner2\""))
        
        let possibleOwner4 = codeOwners.ownersForPath("bb")
        XCTAssertNil(possibleOwner4)
        
        let possibleOwner5 = codeOwners.ownersForPath("/a/some/file")
        let defaultOwner5 = try XCTUnwrap(possibleOwner5)
        XCTAssertTrue(defaultOwner5.contains("\"@owner1\""))
    }
}

// MARK: - Ported from datadog-ci-rb spec/datadog/ci/codeowners/matcher_spec.rb
// https://github.com/DataDog/datadog-ci-rb/blob/main/spec/datadog/ci/codeowners/matcher_spec.rb
// Swift API: ownersForPath returns "[\"@owner1\",\"@owner2\"]" or nil (Ruby list_owners returns [String] or nil)
class CodeOwnersMatcherSpecTests: XCTestCase {

    /// expected: nil = expect nil result, [] = expect empty list (Swift may return nil if it doesn't store owner-less rules), [String] = expect that list
    func expectOwners(_ result: String?, equals expected: [String]?) {
        guard let expected = expected else {
            XCTAssertNil(result, "Expected nil")
            return
        }
        if expected.isEmpty {
            // Ruby returns [] for match-with-no-owners; Swift may return nil
            XCTAssertTrue(result == "[]" || result == nil, "Expected [] or nil, got \(result ?? "nil")")
            return
        }
        let formatted = "[\"" + expected.joined(separator: "\",\"") + "\"]"
        XCTAssertEqual(result, formatted, "Expected \(formatted)")
    }

    // MARK: - Provided codeowners path does not exist (N/A for init(content:) - we test empty content)
    func testMatcher_codeownersPathDoesNotExist_returnsNil() throws {
        let codeOwners = try CodeOwners(parsing: "")
        expectOwners(codeOwners.ownersForPath("file.rb"), equals: nil)
    }

    // MARK: - When the codeowners file is empty
    func testMatcher_emptyFile_returnsNil() throws {
        let codeOwners = try CodeOwners(parsing: "")
        expectOwners(codeOwners.ownersForPath("file.rb"), equals: nil)
    }

    // MARK: - When the codeowners file contains matching patterns
    func testMatcher_matchingPatterns_returnsListOfOwners() throws {
        let codeownersContent = """
        # Comment line
        /path/to/*.rb @owner3
        /path/to/file.rb @owner1 @owner2 #This is an inline comment.

        /path/to/a/**/z @owner4

        /path/to/module/**/** @owner5
        /path/to/folder/** @owner6
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/path/to/file.rb"), equals: ["@owner1", "@owner2"])
        expectOwners(codeOwners.ownersForPath("/path/to/subfolder/file.rb"), equals: nil)
        expectOwners(codeOwners.ownersForPath("/path/to/another_file.rb"), equals: ["@owner3"])

        expectOwners(codeOwners.ownersForPath("/path/to/a/z/file.rb"), equals: ["@owner4"])
        expectOwners(codeOwners.ownersForPath("/path/to/a/c/z/file.rb"), equals: ["@owner4"])
        expectOwners(codeOwners.ownersForPath("/path/to/a/c/d/z/file.rb"), equals: ["@owner4"])
        expectOwners(codeOwners.ownersForPath("/path/to/a/c/d/z/y/file.rb"), equals: nil)

        expectOwners(codeOwners.ownersForPath("/path/to/module/file.rb"), equals: ["@owner5"])
        expectOwners(codeOwners.ownersForPath("/path/to/module/submodule/file.rb"), equals: ["@owner5"])
        expectOwners(codeOwners.ownersForPath("/path/to/module/submodule/subsubmodule/file.rb"), equals: ["@owner5"])

        expectOwners(codeOwners.ownersForPath("/path/to/folder/file.rb"), equals: ["@owner6"])
        expectOwners(codeOwners.ownersForPath("/path/to/folder/subfolder/file.rb"), equals: ["@owner6"])
    }

    // MARK: - When the codeowners file contains non-matching patterns
    func testMatcher_nonMatchingPatterns_returnsNil() throws {
        let codeownersContent = """
        /path/to/file.rb @owner1
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/path/to/another_file.rb"), equals: nil)
    }

    // MARK: - When the codeowners file contains comments and empty lines
    func testMatcher_commentsAndEmptyLines_returnsListOfOwners() throws {
        let codeownersContent = """
        # Comment line
        /path/to/*.rb @owner2

        # Another comment line
        /path/to/file.rb @owner1
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/path/to/file.rb"), equals: ["@owner1"])
        expectOwners(codeOwners.ownersForPath("/path/to/another_file.rb"), equals: ["@owner2"])
        expectOwners(codeOwners.ownersForPath("/path/to/subfolder/file.rb"), equals: nil)
    }

    // MARK: - When the codeowners file contains section lines
    func testMatcher_sectionLines_returnsListOfOwners() throws {
        let codeownersContent = """
        [section1]
        /path/to/*.rb @owner2

        [section2][2]
        /path/to/file.rb @owner1
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/path/to/file.rb"), equals: ["@owner2", "@owner1"])
        expectOwners(codeOwners.ownersForPath("/path/to/another_file.rb"), equals: ["@owner2"])
    }

    // MARK: - With global pattern
    func testMatcher_globalPattern_returnsMatchingPattern() throws {
        let codeownersContent = """
        * @owner1
        /path/to/file.rb @owner2
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/path/to/file.rb"), equals: ["@owner2"])
        expectOwners(codeOwners.ownersForPath("/path/to/another_file.rb"), equals: ["@owner1"])
    }

    // MARK: - With file extension patterns
    func testMatcher_fileExtensionPatterns_returnsListOfOwners() throws {
        let codeownersContent = """
        *.js @jsowner
        *.go @Datadog/goowner
        *.java
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/path/to/file.js"), equals: ["@jsowner"])
        expectOwners(codeOwners.ownersForPath("main.go"), equals: ["@Datadog/goowner"])
        expectOwners(codeOwners.ownersForPath("/main.go"), equals: ["@Datadog/goowner"])
        expectOwners(codeOwners.ownersForPath("file.rb"), equals: nil)
        // Ruby: AbstractFactory.java matches *.java with no owners → returns []
        expectOwners(codeOwners.ownersForPath("AbstractFactory.java"), equals: [])
    }

    // MARK: - When matching directory and all subdirectories
    func testMatcher_directoryAndSubdirectories_returnsListOfOwners() throws {
        let codeownersContent = """
        * @owner

        # /build/logs/ directory and subdirectories
        /build/logs/ @buildlogsowner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/build/logs/logs.txt"), equals: ["@buildlogsowner"])
        expectOwners(codeOwners.ownersForPath("build/logs/2022/logs.txt"), equals: ["@buildlogsowner"])
        expectOwners(codeOwners.ownersForPath("/build/logs/2022/12/logs.txt"), equals: ["@buildlogsowner"])
        expectOwners(codeOwners.ownersForPath("build/logs/2022/12/logs.txt"), equals: ["@buildlogsowner"])

        expectOwners(codeOwners.ownersForPath("/service/build/logs/logs.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("service/build/build.pkg"), equals: ["@owner"])
    }

    // MARK: - When matching files in a directory but not in subdirectories
    func testMatcher_docsStar_notInSubdirectories() throws {
        let codeownersContent = """
        * @owner

        # docs/* matches docs/getting-started.md but not docs/build-app/troubleshooting.md
        docs/*  docs@example.com
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("docs/getting-started.md"), equals: ["docs@example.com"])
        expectOwners(codeOwners.ownersForPath("docs/build-app/troubleshooting.md"), equals: ["@owner"])

        expectOwners(codeOwners.ownersForPath("some/folder/docs/getting-started.md"), equals: ["docs@example.com"])
        expectOwners(codeOwners.ownersForPath("some/folder/docs/build-app/troubleshooting.md"), equals: ["@owner"])

        expectOwners(codeOwners.ownersForPath("/root/docs/getting-started.md"), equals: ["docs@example.com"])
        expectOwners(codeOwners.ownersForPath("/root/folder/docs/build-app/troubleshooting.md"), equals: ["@owner"])
    }

    // MARK: - When matching files in any subdirectory anywhere (apps/)
    func testMatcher_appsDirectoryAnywhere_returnsListOfOwners() throws {
        let codeownersContent = """
        * @owner

        # @octocat owns any file in an apps directory anywhere
        apps/ @octocat
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/apps/file.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/some/folder/apps/file.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("some/folder/apps/1/file.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("some/folder/apps/1/2/file.txt"), equals: ["@octocat"])

        expectOwners(codeOwners.ownersForPath("file.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/file.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("some/folder/file.txt"), equals: ["@owner"])
    }

    // MARK: - When pattern starts from **
    func testMatcher_doubleStarLogs_returnsListOfOwners() throws {
        let codeownersContent = """
        * @owner

        # **/logs - any /logs directory
        **/logs @octocat
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/build/logs/logs.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/scripts/logs/logs.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/deeply/nested/logs/logs.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/logs/logs.txt"), equals: ["@octocat"])

        expectOwners(codeOwners.ownersForPath("file.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/file.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("some/folder/file.txt"), equals: ["@owner"])
    }

    // MARK: - When matching anywhere in directory except specific subdirectory
    func testMatcher_appsExceptGithub_returnsListOfOwners() throws {
        let codeownersContent = """
        * @owner

        /apps/ @octocat
        /apps/github
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/apps/logs.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/apps/1/logs.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/apps/deeply/nested/logs/logs.txt"), equals: ["@octocat"])

        expectOwners(codeOwners.ownersForPath("apps/github"), equals: [])
        expectOwners(codeOwners.ownersForPath("apps/github/codeowners"), equals: [])

        expectOwners(codeOwners.ownersForPath("other/file.txt"), equals: ["@owner"])
    }

    // MARK: - Negated path support (! prefix, GitLab-style exclusions)
    func testMatcher_negatedPath_excludesMatchingPaths() throws {
        let codeownersContent = """
        * @owner

        /apps/ @octocat
        !/apps/github
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/apps/logs.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/apps/1/logs.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/apps/deeply/nested/logs/logs.txt"), equals: ["@octocat"])

        expectOwners(codeOwners.ownersForPath("apps/github"), equals: [])
        expectOwners(codeOwners.ownersForPath("apps/github/codeowners"), equals: [])

        expectOwners(codeOwners.ownersForPath("other/file.txt"), equals: ["@owner"])
    }

    // MARK: - Path exclusion with multiple sections (GitLab documentation examples)
    // Exclusions apply per section. If you need different exclusions for different owners, use multiple sections:
    // https://docs.gitlab.com/user/project/codeowners/reference/#exclusion-patterns
    func testMatcher_negatedPath_multipleSections_exclusionPerSection() throws {
        let codeownersContent = """
        * @username
        !pom.xml

        [Ruby]
        *.rb @ruby-team
        !/config/**/*.rb

        [Config]
        /config/ @ops-team
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        // pom.xml: excluded from default section. No other section matches. Result: nil
        expectOwners(codeOwners.ownersForPath("pom.xml"), equals: [])

        // /lib/foo.rb: default + Ruby section (not excluded). Config doesn't match.
        expectOwners(codeOwners.ownersForPath("/lib/foo.rb"), equals: ["@username", "@ruby-team"])

        // /config/routes.rb: default gives @username. Ruby: *.rb matches but !/config/**/*.rb excludes.
        // Config: /config/ matches @ops-team. Config Ruby files don't need Ruby approval but still need ops.
        expectOwners(codeOwners.ownersForPath("/config/routes.rb"), equals: ["@username", "@ops-team"])

        // /config/settings.yml: default + Config only (not a Ruby file)
        expectOwners(codeOwners.ownersForPath("/config/settings.yml"), equals: ["@username", "@ops-team"])
    }

    /// Exclusion in one section does not block owners from another section.
    /// From GitLab: "Files matching an exclusion pattern do not require code owner approval for that section."
    func testMatcher_negatedPath_excludedInOneSection_canGetOwnersFromAnother() throws {
        let codeownersContent = """
        * @username
        !pom.xml

        [Build]
        pom.xml @build-team
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        // pom.xml excluded from default section, but [Build] section still assigns @build-team
        expectOwners(codeOwners.ownersForPath("pom.xml"), equals: ["@build-team"])
        expectOwners(codeOwners.ownersForPath("/pom.xml"), equals: ["@build-team"])
    }

    // MARK: - GitLab format with default owner per section
    func testMatcher_gitlabDefaultOwnerPerSection_returnsListOfOwners() throws {
        let codeownersContent = """
        # Default owners per section
        [Development] @dev-team
        *
        README.md @docs-team
        data-models/ @data-science-team

        [Testing]
        *_spec.rb @qa-team
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("data-models/model"), equals: ["@data-science-team"])
        expectOwners(codeOwners.ownersForPath("data-models/search/model"), equals: ["@data-science-team"])

        expectOwners(codeOwners.ownersForPath("README.md"), equals: ["@docs-team"])
        expectOwners(codeOwners.ownersForPath("/README.md"), equals: ["@docs-team"])

        expectOwners(codeOwners.ownersForPath("apps/main.go"), equals: ["@dev-team"])
        expectOwners(codeOwners.ownersForPath(".gitignore"), equals: ["@dev-team"])

        expectOwners(codeOwners.ownersForPath("spec/helpers_spec.rb"), equals: ["@dev-team", "@qa-team"])
    }
}

// MARK: - Tests for known parser issues
// These tests document correct behavior per CODEOWNERS spec.
class CodeOwnersParserIssueTests: XCTestCase {

    func expectOwners(_ result: String?, equals expected: [String]?) {
        guard let expected = expected else {
            XCTAssertNil(result, "Expected nil, got \(result ?? "nil")")
            return
        }
        if expected.isEmpty {
            XCTAssertTrue(result == "[]" || result == nil, "Expected [] or nil, got \(result ?? "nil")")
            return
        }
        let formatted = "[\"" + expected.joined(separator: "\",\"") + "\"]"
        XCTAssertEqual(result, formatted, "Expected \(formatted)")
    }

    // MARK: Issue #1: ? wildcard should match any single character except /

    func testQuestionMarkWildcard_matchesSingleCharacter() throws {
        let codeownersContent = """
        file?.txt @owner
        file2\\?.txt @owner2
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("fileA.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("file1.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("file2?.txt"), equals: ["@owner2"])
        expectOwners(codeOwners.ownersForPath("file2A.txt"), equals: nil)

        expectOwners(codeOwners.ownersForPath("file.txt"), equals: nil)
        expectOwners(codeOwners.ownersForPath("fileAB.txt"), equals: nil)
        expectOwners(codeOwners.ownersForPath("file/.txt"), equals: nil)
        
    }

    // MARK: Issue #2: **/ should enforce path-segment boundaries

    func testDoubleStarSlash_shouldNotMatchPartialSegments() throws {
        let codeownersContent = """
        * @owner
        **/logs @octocat
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/build/logs/file.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/logs/file.txt"), equals: ["@octocat"])

        // "logs" as a substring of another segment must NOT match
        expectOwners(codeOwners.ownersForPath("/prologs/file.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/catalogsys/file.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/mylogs/file.txt"), equals: ["@owner"])
    }

    // MARK: Issue #3: **/name should match all subdirectory depths (equivalent to bare name)

    func testDoubleStarName_matchesAllSubdirectoryDepths() throws {
        let codeownersContent = """
        * @owner
        **/logs @octocat
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        // One level deep
        expectOwners(codeOwners.ownersForPath("/build/logs/file.txt"), equals: ["@octocat"])

        // Multiple levels deep — **/logs should be equivalent to logs
        expectOwners(codeOwners.ownersForPath("/build/logs/sub/file.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/build/logs/sub/deep/file.txt"), equals: ["@octocat"])
        expectOwners(codeOwners.ownersForPath("/logs/a/b/c/file.txt"), equals: ["@octocat"])
    }

    // MARK: Issue #4: Chained replacingOccurrences mis-processes \\# and \\ sequences

    func testEscapeChaining_doubleBackslashBeforeHash() throws {
        // CODEOWNERS content: \\#file.rb @owner
        // \\  = escaped backslash → literal \
        // #file.rb  = literal (since \# was NOT used; but after chained replacement,
        //             the \# produced by step 1 is consumed by step 3)
        // Correct unescaped path: \#file.rb
        let codeownersContent = ##"\\#file.rb @owner"##
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("\\#file.rb"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("#file.rb"), equals: nil)
    }

    // MARK: Issue #5: _firstUnescapedIndex should count consecutive backslashes

    func testBackslashCounting_evenBackslashesDoNotEscapeHash() throws {
        // CODEOWNERS line: /path/file @owner1 @owner2 \\#this is a comment
        // The \\ is an escaped backslash, then # starts an inline comment.
        // Only @owner1 and @owner2 should be parsed as owners.
        let codeownersContent = ##"/path/file @owner1 @owner2 \\#this is a comment"##
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        let result = codeOwners.ownersForPath("/path/file")
        let unwrapped = try XCTUnwrap(result)
        XCTAssertTrue(unwrapped.contains("\"@owner1\""), "Should contain @owner1")
        XCTAssertTrue(unwrapped.contains("\"@owner2\""), "Should contain @owner2")
        XCTAssertFalse(unwrapped.contains("comment"), "Comment text should not appear as owner")
    }

    // MARK: Issue #6: Unicode paths — NSRange length must use UTF-16 count

    func testUnicodePaths_emojiCharactersInPath() throws {
        let codeownersContent = """
        *.txt @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        // 🎉 is 1 Swift Character but 2 UTF-16 code units.
        // Using String.count for NSRange makes the range too short.
        expectOwners(codeOwners.ownersForPath("/🎉.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/path/🎉test.txt"), equals: ["@owner"])
    }

    func testUnicodePaths_flagEmojiInPath() throws {
        let codeownersContent = """
        /docs/ @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        // 🇺🇦 is 1 Swift Character but 4 UTF-16 code units.
        expectOwners(codeOwners.ownersForPath("/docs/readme-🇺🇦.md"), equals: ["@owner"])
    }

    // MARK: Issue #7: Section approval count [n] leaking as owner with unusual spacing

    func testSectionApprovalCount_notLeakedAsOwner() throws {
        // [Section] [2] @section-owner — the [2] is an approval count, not an owner
        let codeownersContent = """
        [Section] [2] @section-owner
        /path/
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        let result = codeOwners.ownersForPath("/path/file.txt")
        let unwrapped = try XCTUnwrap(result)
        XCTAssertTrue(unwrapped.contains("\"@section-owner\""), "Should contain @section-owner")
        XCTAssertFalse(unwrapped.contains("[2]"), "Approval count [2] should not appear as owner")
    }

    // MARK: - Character range support [...]

    func testCharacterRange_basicRange_matchesSingleCharInRange() throws {
        let codeownersContent = """
        /src/file[0-9].txt @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/src/file0.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/src/file5.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/src/file9.txt"), equals: ["@owner"])

        expectOwners(codeOwners.ownersForPath("/src/fileA.txt"), equals: nil)
        expectOwners(codeOwners.ownersForPath("/src/file.txt"), equals: nil)
        expectOwners(codeOwners.ownersForPath("/src/file12.txt"), equals: nil)
    }

    func testCharacterRange_characterSet_matchesListedChars() throws {
        let codeownersContent = """
        /src/file[abc].txt @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/src/filea.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/src/fileb.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/src/filec.txt"), equals: ["@owner"])

        expectOwners(codeOwners.ownersForPath("/src/filed.txt"), equals: nil)
        expectOwners(codeOwners.ownersForPath("/src/file.txt"), equals: nil)
    }

    func testCharacterRange_negatedWithExclamation_excludesChars() throws {
        let codeownersContent = """
        * @fallback
        /src/file[!0-9].txt @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/src/filea.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/src/fileZ.txt"), equals: ["@owner"])

        expectOwners(codeOwners.ownersForPath("/src/file5.txt"), equals: ["@fallback"])
        expectOwners(codeOwners.ownersForPath("/src/file0.txt"), equals: ["@fallback"])
    }

    func testCharacterRange_alphabeticRange() throws {
        let codeownersContent = """
        /docs/chapter-[a-f].md @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/docs/chapter-a.md"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/docs/chapter-f.md"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/docs/chapter-c.md"), equals: ["@owner"])

        expectOwners(codeOwners.ownersForPath("/docs/chapter-g.md"), equals: nil)
        expectOwners(codeOwners.ownersForPath("/docs/chapter-z.md"), equals: nil)
    }

    func testCharacterRange_atEndOfPattern_matchesSubdirectories() throws {
        let codeownersContent = """
        /src/module[AB] @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/src/moduleA"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/src/moduleB"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/src/moduleA/file.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/src/moduleB/sub/file.txt"), equals: ["@owner"])

        expectOwners(codeOwners.ownersForPath("/src/moduleC"), equals: nil)
    }

    func testCharacterRange_multipleRanges_inSamePattern() throws {
        let codeownersContent = """
        /src/v[0-9].[0-9].txt @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/src/v1.0.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/src/v3.5.txt"), equals: ["@owner"])

        expectOwners(codeOwners.ownersForPath("/src/v1.txt"), equals: nil)
        expectOwners(codeOwners.ownersForPath("/src/va.0.txt"), equals: nil)
    }

    func testCharacterRange_withWildcards_combinedPatterns() throws {
        let codeownersContent = """
        **/log[0-9].txt @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/log1.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/var/log5.txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/a/b/c/log9.txt"), equals: ["@owner"])

        expectOwners(codeOwners.ownersForPath("/logA.txt"), equals: nil)
    }

    func testCharacterRange_escapedBracket_treatedAsLiteral() throws {
        let codeownersContent = ##"/src/\[file\].txt @owner"##
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/src/[file].txt"), equals: ["@owner"])
        expectOwners(codeOwners.ownersForPath("/src/f.txt"), equals: nil)
    }

    func testCharacterRange_unmatchedOpenBracket_treatedAsLiteral() throws {
        let codeownersContent = """
        /src/[file.txt @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)

        expectOwners(codeOwners.ownersForPath("/src/[file.txt"), equals: ["@owner"])
    }

    // MARK: - Regression tests for fixed issues

    func testRegression_caretAtStartOfLine_treatedAsPath() throws {
        let codeownersContent = """
        ^test.txt @owner
        """
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("^test.txt"), equals: ["@owner"])
    }

    func testRegression_emptyNegatedPattern_throwsInsteadOfCrash() throws {
        let codeownersContent = """
        * @owner
        !
        """
        XCTAssertThrowsError(try CodeOwners(parsing: codeownersContent))
    }

    func testRegression_tabSeparator_betweenPathAndOwners() throws {
        let codeownersContent = "/path/to/file\t@owner"
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/path/to/file"), equals: ["@owner"])
    }

    func testRegression_tabSeparator_multipleOwners() throws {
        let codeownersContent = "/path/to/file\t@owner1\t@owner2"
        let codeOwners = try CodeOwners(parsing: codeownersContent)
        expectOwners(codeOwners.ownersForPath("/path/to/file"), equals: ["@owner1", "@owner2"])
    }
}
