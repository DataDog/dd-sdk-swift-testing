/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import DatadogSDKTesting
import XCTest

class GitInfoTests: XCTestCase {
    func testNoCommits() throws {
        let bundle = Bundle(for: type(of: self))
        let fixturesURL = bundle.resourceURL!

        let noCommitsFolder = fixturesURL.appendingPathComponent("git")
            .appendingPathComponent("no_commits").appendingPathComponent("git")

        XCTAssertTrue(try noCommitsFolder.checkPromisedItemIsReachable())
        XCTAssertThrowsError(try GitInfo(gitFolder: noCommitsFolder))
    }

    func testNoObjects() throws {
        let bundle = Bundle(for: type(of: self))
        let fixturesURL = bundle.resourceURL!

        let withCommitsFolder = fixturesURL.appendingPathComponent("git")
            .appendingPathComponent("no_objects").appendingPathComponent("git")

        XCTAssertTrue(try withCommitsFolder.checkPromisedItemIsReachable())
        let gitInfo = try GitInfo(gitFolder: withCommitsFolder)
    }

    func testWithCommits() throws {
        let bundle = Bundle(for: type(of: self))
        let fixturesURL = bundle.resourceURL!

        let withCommitsFolder = fixturesURL.appendingPathComponent("git")
            .appendingPathComponent("with_commits").appendingPathComponent("git")

        XCTAssertTrue(try withCommitsFolder.checkPromisedItemIsReachable())
        let gitInfo = try GitInfo(gitFolder: withCommitsFolder)
        XCTAssertEqual(gitInfo.commit, "0797c248e019314fc1d91a483e859b32f4509953")
        XCTAssertEqual(gitInfo.repository, "git@github.com:DataDog/dd-sdk-swift-testing.git")
        XCTAssertEqual(gitInfo.branch, "master")
        XCTAssertEqual(gitInfo.commitMessage, "This is a commit message")
        XCTAssertEqual(gitInfo.authorName, "John Doe")
        XCTAssertEqual(gitInfo.authorEmail, "john@doe.com")
        XCTAssertEqual(gitInfo.committerName, "Jane Doe")
        XCTAssertEqual(gitInfo.committerEmail, "jane@doe.com")
    }

    func testWithCommitsNoRefs() throws {
        let bundle = Bundle(for: type(of: self))
        let fixturesURL = bundle.resourceURL!

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
        let bundle = Bundle(for: type(of: self))
        let fixturesURL = bundle.resourceURL!

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
}
