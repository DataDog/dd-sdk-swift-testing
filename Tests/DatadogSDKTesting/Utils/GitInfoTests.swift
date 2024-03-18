/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class GitInfoTests: XCTestCase {
    let fixturesURL: URL = {
        let bundle = Bundle(for: GitInfoTests.self)
        return bundle.resourceURL!.appendingPathComponent("fixtures")
    }()
    
    func testNoCommits() throws {
        let noCommitsFolder = fixturesURL.appendingPathComponent("git")
            .appendingPathComponent("no_commits").appendingPathComponent("git")

        XCTAssertTrue(try noCommitsFolder.checkPromisedItemIsReachable())
        XCTAssertThrowsError(try GitInfo(gitFolder: noCommitsFolder))
    }

    func testNoObjects() throws {
        let withCommitsFolder = fixturesURL.appendingPathComponent("git")
            .appendingPathComponent("no_objects").appendingPathComponent("git")

        XCTAssertTrue(try withCommitsFolder.checkPromisedItemIsReachable())
        _ = try GitInfo(gitFolder: withCommitsFolder)
    }

    func testWithCommits() throws {
        let withCommitsFolder = fixturesURL.appendingPathComponent("git")
            .appendingPathComponent("with_commits").appendingPathComponent("git")

        XCTAssertTrue(try withCommitsFolder.checkPromisedItemIsReachable())
        let gitInfo = try GitInfo(gitFolder: withCommitsFolder)
        XCTAssertEqual(gitInfo.commit, "0797c248e019314fc1d91a483e859b32f4509953")
        XCTAssertEqual(gitInfo.repository, "git@github.com:DataDog/dd-sdk-swift-testing.git")
        XCTAssertEqual(gitInfo.branch, "refs/heads/master")
        XCTAssertEqual(gitInfo.commitMessage, "This is a commit message")
        XCTAssertEqual(gitInfo.authorName, "John Doe")
        XCTAssertEqual(gitInfo.authorEmail, "john@doe.com")
        XCTAssertEqual(gitInfo.committerName, "Jane Doe")
        XCTAssertEqual(gitInfo.committerEmail, "jane@doe.com")
    }

    func testWithCommitsNoRefs() throws {
        let withCommitsFolder = fixturesURL.appendingPathComponent("git")
            .appendingPathComponent("with_commits_no_refs").appendingPathComponent("git")

        XCTAssertTrue(try withCommitsFolder.checkPromisedItemIsReachable())
        let gitInfo = try GitInfo(gitFolder: withCommitsFolder)
        XCTAssertEqual(gitInfo.commitMessage, "This is a commit message")
        XCTAssertEqual(gitInfo.authorName, "John Doe")
        XCTAssertEqual(gitInfo.authorEmail, "john@doe.com")
        XCTAssertEqual(gitInfo.committerName, "Jane Doe")
        XCTAssertEqual(gitInfo.committerEmail, "jane@doe.com")
    }

    func testWithTag() throws {
        let withCommitsFolder = fixturesURL.appendingPathComponent("git")
            .appendingPathComponent("with_tag").appendingPathComponent("git")

        XCTAssertTrue(try withCommitsFolder.checkPromisedItemIsReachable())
        let gitInfo = try GitInfo(gitFolder: withCommitsFolder)
        XCTAssertEqual(gitInfo.commitMessage, "This is a commit message")
        XCTAssertEqual(gitInfo.authorName, "John Doe")
        XCTAssertEqual(gitInfo.authorEmail, "john@doe.com")
        XCTAssertEqual(gitInfo.committerName, "Jane Doe")
        XCTAssertEqual(gitInfo.committerEmail, "jane@doe.com")
    }

    func testWithPackFiles() throws {
        let packFilesFolder = fixturesURL.appendingPathComponent("git")
            .appendingPathComponent("pack_files").appendingPathComponent("git")

        XCTAssertTrue(try packFilesFolder.checkPromisedItemIsReachable())
        let gitInfo = try GitInfo(gitFolder: packFilesFolder)
        XCTAssertEqual(gitInfo.commit, "63902373bbe01489ae104f5fc5561eb578dec196")
        XCTAssertEqual(gitInfo.repository, "git@github.com:DataDog/dd-sdk-swift-testing.git")
        XCTAssertEqual(gitInfo.branch, "refs/heads/main")
        XCTAssertEqual(gitInfo.commitMessage, "Add possibility to change endpoint, they use `DD_ENDPOINT` environment variable: \"us\", \"eu\", \"gov\"\nMove ENVIRONMENT_TRACER handling to DDEnvironmentValues\nAdd InMemoryExporter when usinf DD_DONT_EXPORT variable (used in testing) so all the Opentelemetry code runs but dont export to backend")
        XCTAssertEqual(gitInfo.authorName, "Ignacio Bonafonte")
        XCTAssertEqual(gitInfo.authorEmail, "nacho.bonafontearruga@datadoghq.com")
        XCTAssertEqual(gitInfo.authorDate, "2021-05-06T08:03:32Z")
        XCTAssertEqual(gitInfo.committerName, "Ignacio Bonafonte")
        XCTAssertEqual(gitInfo.committerEmail, "nacho.bonafontearruga@datadoghq.com")
        XCTAssertEqual(gitInfo.committerDate, "2021-05-06T08:03:32Z")
    }
}
