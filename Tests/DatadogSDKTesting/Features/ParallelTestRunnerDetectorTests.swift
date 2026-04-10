/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

final class ParallelTestRunnerDetectorTests: XCTestCase {

    // MARK: - isTestPlanNonParallel (targetName: nil — any-target fallback)

    func testNonParallelTestPlanReturnsTrueWhenAnyTargetHasParallelizableFalse() {
        let json = testPlanJSON(targets: [
            ["parallelizable": false, "target": ["name": "TargetA"]],
            ["target": ["name": "TargetB"]]
        ])
        XCTAssertEqual(ParallelTestRunnerDetector.isTestPlanNonParallel(data: json,
                                                                         targetName: nil), true)
    }

    func testParallelTestPlanReturnsFalseWhenAllTargetsParallelizableTrue() {
        let json = testPlanJSON(targets: [
            ["parallelizable": true, "target": ["name": "TargetA"]],
            ["parallelizable": true, "target": ["name": "TargetB"]]
        ])
        XCTAssertEqual(ParallelTestRunnerDetector.isTestPlanNonParallel(data: json,
                                                                         targetName: nil), false)
    }

    func testDefaultTestPlanReturnsFalseWhenNoParallelizableKey() {
        let json = testPlanJSON(targets: [["target": ["name": "TargetA"]]])
        XCTAssertEqual(ParallelTestRunnerDetector.isTestPlanNonParallel(data: json,
                                                                         targetName: nil), false)
    }

    func testEmptyTestTargetsReturnsNil() {
        let json = testPlanJSON(targets: [])
        XCTAssertNil(ParallelTestRunnerDetector.isTestPlanNonParallel(data: json, targetName: nil))
    }

    func testMalformedTestPlanReturnsNil() {
        let invalid = "not json".data(using: .utf8)!
        XCTAssertNil(ParallelTestRunnerDetector.isTestPlanNonParallel(data: invalid,
                                                                       targetName: nil))
    }

    // MARK: - isTestPlanNonParallel (targetName provided)

    func testTargetFoundWithParallelizableFalseReturnsTrue() {
        let json = testPlanJSON(targets: [
            ["parallelizable": false, "target": ["name": "MyTarget"]],
            ["parallelizable": true,  "target": ["name": "OtherTarget"]]
        ])
        XCTAssertEqual(ParallelTestRunnerDetector.isTestPlanNonParallel(data: json,
                                                                         targetName: "MyTarget"), true)
    }

    func testTargetFoundWithParallelizableTrueReturnsFalse() {
        let json = testPlanJSON(targets: [
            ["parallelizable": false, "target": ["name": "OtherTarget"]],
            ["parallelizable": true,  "target": ["name": "MyTarget"]]
        ])
        XCTAssertEqual(ParallelTestRunnerDetector.isTestPlanNonParallel(data: json,
                                                                         targetName: "MyTarget"), false)
    }

    func testTargetFoundWithoutParallelizableKeyReturnsFalse() {
        // Absent key means Xcode default: parallel enabled
        let json = testPlanJSON(targets: [
            ["target": ["name": "MyTarget"]]
        ])
        XCTAssertEqual(ParallelTestRunnerDetector.isTestPlanNonParallel(data: json,
                                                                         targetName: "MyTarget"), false)
    }

    func testTargetNotFoundReturnsNil() {
        let json = testPlanJSON(targets: [
            ["parallelizable": false, "target": ["name": "OtherTarget"]]
        ])
        XCTAssertNil(ParallelTestRunnerDetector.isTestPlanNonParallel(data: json,
                                                                       targetName: "MissingTarget"))
    }

    // MARK: - findSchemeFile

    func testFindSchemeFileInXcodeproj() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        try createSchemeDir(in: tmpDir, container: "MyProject.xcodeproj",
                            schemeName: "MyScheme", content: "")

        let found = ParallelTestRunnerDetector.findSchemeFile(named: "MyScheme", in: tmpDir)
        XCTAssertEqual(found?.lastPathComponent, "MyScheme.xcscheme")
    }

    func testFindSchemeFileInXcworkspace() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        try createSchemeDir(in: tmpDir, container: "MyWorkspace.xcworkspace",
                            schemeName: "WS", content: "")

        let found = ParallelTestRunnerDetector.findSchemeFile(named: "WS", in: tmpDir)
        XCTAssertEqual(found?.lastPathComponent, "WS.xcscheme")
    }

    func testFindSchemeFileReturnsNilWhenNotFound() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }
        XCTAssertNil(ParallelTestRunnerDetector.findSchemeFile(named: "Missing", in: tmpDir))
    }

    // MARK: - findFile

    func testFindFileInRootDirectory() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        let filePath = (tmpDir as NSString).appendingPathComponent("Plan.xctestplan")
        try "".write(toFile: filePath, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            ParallelTestRunnerDetector.findFile(named: "Plan.xctestplan", in: tmpDir, maxDepth: 0),
            filePath
        )
    }

    func testFindFileInSubdirectory() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        let subDir = (tmpDir as NSString).appendingPathComponent("Tests/Suite")
        try FileManager.default.createDirectory(atPath: subDir, withIntermediateDirectories: true)
        let filePath = (subDir as NSString).appendingPathComponent("Plan.xctestplan")
        try "".write(toFile: filePath, atomically: true, encoding: .utf8)

        XCTAssertNotNil(
            ParallelTestRunnerDetector.findFile(named: "Plan.xctestplan", in: tmpDir, maxDepth: 3)
        )
    }

    func testFindFileReturnsNilWhenDepthExceeded() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        let deepDir = (tmpDir as NSString).appendingPathComponent("a/b/c/d")
        try FileManager.default.createDirectory(atPath: deepDir, withIntermediateDirectories: true)
        let filePath = (deepDir as NSString).appendingPathComponent("Plan.xctestplan")
        try "".write(toFile: filePath, atomically: true, encoding: .utf8)

        XCTAssertNil(
            ParallelTestRunnerDetector.findFile(named: "Plan.xctestplan", in: tmpDir, maxDepth: 2)
        )
    }

    func testFindFileSkipsXcodeprojectDirectories() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        let xcprojDir = (tmpDir as NSString).appendingPathComponent("X.xcodeproj/hidden")
        try FileManager.default.createDirectory(atPath: xcprojDir, withIntermediateDirectories: true)
        let filePath = (xcprojDir as NSString).appendingPathComponent("Plan.xctestplan")
        try "".write(toFile: filePath, atomically: true, encoding: .utf8)

        XCTAssertNil(
            ParallelTestRunnerDetector.findFile(named: "Plan.xctestplan", in: tmpDir, maxDepth: 5)
        )
    }

    // MARK: - isParallelizationDisabled: env-var routing

    func testNoEnvVarsUsesProcessArguments() {
        let env = ProcessEnvironmentReader(environment: [:], infoDictionary: [:])
        // --no-parallel is not present in the actual unit-test process arguments
        XCTAssertFalse(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                             sourceRoot: nil,
                                                                             targetName: nil))
    }

    func testTestPlanNameSetButNoSourceRootReturnsFalse() {
        let env = ProcessEnvironmentReader(
            environment: ["XCODE_TEST_PLAN_NAME": "SomePlan"], infoDictionary: [:])
        XCTAssertFalse(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                             sourceRoot: nil,
                                                                             targetName: "T"))
    }

    func testSchemeNameSetButNoSourceRootReturnsFalse() {
        let env = ProcessEnvironmentReader(
            environment: ["XCODE_SCHEME_NAME": "SomeScheme"], infoDictionary: [:])
        XCTAssertFalse(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                             sourceRoot: nil,
                                                                             targetName: "T"))
    }

    // MARK: - isParallelizationDisabled: test plan path

    func testTestPlanNonParallelForMatchingTargetReturnsTrue() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        let json = testPlanJSON(targets: [
            ["parallelizable": false, "target": ["name": "MyTests"]],
            ["parallelizable": true,  "target": ["name": "OtherTests"]]
        ])
        try json.write(to: URL(fileURLWithPath:
            (tmpDir as NSString).appendingPathComponent("MyPlan.xctestplan")))

        let env = ProcessEnvironmentReader(
            environment: ["XCODE_TEST_PLAN_NAME": "MyPlan"], infoDictionary: [:])
        XCTAssertTrue(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                            sourceRoot: tmpDir,
                                                                            targetName: "MyTests"))
    }

    func testTestPlanParallelForMatchingTargetReturnsFalse() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        let json = testPlanJSON(targets: [
            ["parallelizable": false, "target": ["name": "OtherTests"]],
            ["parallelizable": true,  "target": ["name": "MyTests"]]
        ])
        try json.write(to: URL(fileURLWithPath:
            (tmpDir as NSString).appendingPathComponent("MyPlan.xctestplan")))

        let env = ProcessEnvironmentReader(
            environment: ["XCODE_TEST_PLAN_NAME": "MyPlan"], infoDictionary: [:])
        XCTAssertFalse(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                             sourceRoot: tmpDir,
                                                                             targetName: "MyTests"))
    }

    func testTestPlanTargetMissingReturnsFalse() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        let json = testPlanJSON(targets: [
            ["parallelizable": false, "target": ["name": "OtherTests"]]
        ])
        try json.write(to: URL(fileURLWithPath:
            (tmpDir as NSString).appendingPathComponent("MyPlan.xctestplan")))

        let env = ProcessEnvironmentReader(
            environment: ["XCODE_TEST_PLAN_NAME": "MyPlan"], infoDictionary: [:])
        // Target not found → nil → false
        XCTAssertFalse(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                             sourceRoot: tmpDir,
                                                                             targetName: "Missing"))
    }

    // MARK: - isParallelizationDisabled: scheme path

    func testSchemeNonParallelForMatchingTargetReturnsTrue() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        try createScheme(named: "MyScheme", in: tmpDir,
                         testableRefs: [("MyTests", "NO"), ("OtherTests", "YES")],
                         hasTestPlan: false)

        let env = ProcessEnvironmentReader(
            environment: ["XCODE_SCHEME_NAME": "MyScheme"], infoDictionary: [:])
        XCTAssertTrue(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                            sourceRoot: tmpDir,
                                                                            targetName: "MyTests"))
    }

    func testSchemeParallelForMatchingTargetReturnsFalse() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        try createScheme(named: "MyScheme", in: tmpDir,
                         testableRefs: [("OtherTests", "NO"), ("MyTests", "YES")],
                         hasTestPlan: false)

        let env = ProcessEnvironmentReader(
            environment: ["XCODE_SCHEME_NAME": "MyScheme"], infoDictionary: [:])
        XCTAssertFalse(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                             sourceRoot: tmpDir,
                                                                             targetName: "MyTests"))
    }

    func testSchemeTargetMissingReturnsFalse() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        try createScheme(named: "MyScheme", in: tmpDir,
                         testableRefs: [("OtherTests", "NO")],
                         hasTestPlan: false)

        let env = ProcessEnvironmentReader(
            environment: ["XCODE_SCHEME_NAME": "MyScheme"], infoDictionary: [:])
        XCTAssertFalse(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                             sourceRoot: tmpDir,
                                                                             targetName: "Missing"))
    }

    func testSchemeWithTestPlanReferenceIgnoredWhenNoTestPlanEnvVar() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        // Scheme has a TestPlans section: detector must defer to test plan and return false
        try createScheme(named: "MyScheme", in: tmpDir,
                         testableRefs: [("MyTests", "NO")],
                         hasTestPlan: true)

        let env = ProcessEnvironmentReader(
            environment: ["XCODE_SCHEME_NAME": "MyScheme"], infoDictionary: [:])
        XCTAssertFalse(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                             sourceRoot: tmpDir,
                                                                             targetName: "MyTests"))
    }

    // MARK: - Precedence: test plan over scheme

    func testTestPlanTakesPrecedenceOverScheme() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        // Non-parallel test plan for target
        let planJSON = testPlanJSON(targets: [
            ["parallelizable": false, "target": ["name": "MyTests"]]
        ])
        try planJSON.write(to: URL(fileURLWithPath:
            (tmpDir as NSString).appendingPathComponent("MyPlan.xctestplan")))

        // Parallel scheme for same target
        try createScheme(named: "MyScheme", in: tmpDir,
                         testableRefs: [("MyTests", "YES")],
                         hasTestPlan: false)

        let env = ProcessEnvironmentReader(
            environment: ["XCODE_TEST_PLAN_NAME": "MyPlan", "XCODE_SCHEME_NAME": "MyScheme"],
            infoDictionary: [:])
        XCTAssertTrue(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                            sourceRoot: tmpDir,
                                                                            targetName: "MyTests"))
    }

    // MARK: - container: path resolution via scheme

    func testSchemeContainerReferenceResolvesTestPlanPath() throws {
        let tmpDir = try makeTempDir()
        defer { cleanup(tmpDir) }

        // Test plan in a sub-directory
        let planSubDir = (tmpDir as NSString).appendingPathComponent("Plans")
        try FileManager.default.createDirectory(atPath: planSubDir, withIntermediateDirectories: true)
        let planJSON = testPlanJSON(targets: [
            ["parallelizable": false, "target": ["name": "MyTests"]]
        ])
        try planJSON.write(to: URL(fileURLWithPath:
            (planSubDir as NSString).appendingPathComponent("MyPlan.xctestplan")))

        // Scheme with container: reference pointing at the plan
        try createScheme(named: "MyScheme", in: tmpDir,
                         testableRefs: [("MyTests", "YES")],
                         hasTestPlan: false,
                         testPlanContainerRef: "container:Plans/MyPlan.xctestplan")

        let env = ProcessEnvironmentReader(
            environment: ["XCODE_TEST_PLAN_NAME": "MyPlan", "XCODE_SCHEME_NAME": "MyScheme"],
            infoDictionary: [:])
        XCTAssertTrue(ParallelTestRunnerDetector.isParallelizationDisabled(env: env,
                                                                            sourceRoot: tmpDir,
                                                                            targetName: "MyTests"))
    }

    // MARK: - Config: tiaSwiftTestingEnabled is Bool?

    func testConfigStoresNilWhenEnvVarNotSet() {
        let env = ProcessEnvironmentReader(environment: [:], infoDictionary: [:])
        let config = Config(env: env)
        XCTAssertNil(config.tiaSwiftTestingEnabled)
    }

    func testConfigStoresTrueWhenEnvVarIsOne() {
        let env = ProcessEnvironmentReader(
            environment: ["DD_SWIFT_TESTING_TEST_IMPACT_ANALYSIS_ENABLED": "1"],
            infoDictionary: [:])
        let config = Config(env: env)
        XCTAssertEqual(config.tiaSwiftTestingEnabled, true)
    }

    func testConfigStoresFalseWhenEnvVarIsZero() {
        let env = ProcessEnvironmentReader(
            environment: ["DD_SWIFT_TESTING_TEST_IMPACT_ANALYSIS_ENABLED": "0"],
            infoDictionary: [:])
        let config = Config(env: env)
        XCTAssertEqual(config.tiaSwiftTestingEnabled, false)
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func testPlanJSON(targets: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["testTargets": targets, "version": 1])
    }

    /// Creates a `<schemeName>.xcscheme` in `<sourceRoot>/MyProject.xcodeproj/xcshareddata/xcschemes/`.
    /// Each element of `testableRefs` is `(blueprintName, parallelizable)`.
    private func createScheme(named name: String,
                               in sourceRoot: String,
                               testableRefs: [(String, String)],
                               hasTestPlan: Bool,
                               testPlanContainerRef: String? = nil) throws {
        let schemesDir = (((sourceRoot as NSString)
            .appendingPathComponent("MyProject.xcodeproj") as NSString)
            .appendingPathComponent("xcshareddata/xcschemes"))
        try FileManager.default.createDirectory(atPath: schemesDir, withIntermediateDirectories: true)

        let testPlansXML: String
        if hasTestPlan || testPlanContainerRef != nil {
            let ref = testPlanContainerRef ?? "container:SomePlan.xctestplan"
            testPlansXML = """
            <TestPlans>
               <TestPlanReference reference = "\(ref)" default = "YES"/>
            </TestPlans>
            """
        } else {
            testPlansXML = ""
        }

        let refsXML = testableRefs.map { (blueprint, parallel) in
            """
               <TestableReference skipped = "NO" parallelizable = "\(parallel)">
                  <BuildableReference
                     BlueprintName = "\(blueprint)"
                     BuildableName = "\(blueprint).xctest"
                     ReferencedContainer = "container:MyProject.xcodeproj">
                  </BuildableReference>
               </TestableReference>
            """
        }.joined(separator: "\n")

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion = "1640" version = "1.7">
           <TestAction buildConfiguration = "Debug">
              \(testPlansXML)
              <Testables>
        \(refsXML)
              </Testables>
           </TestAction>
        </Scheme>
        """

        let schemePath = (schemesDir as NSString).appendingPathComponent("\(name).xcscheme")
        try xml.write(toFile: schemePath, atomically: true, encoding: .utf8)
    }

    /// Creates an empty scheme file at the standard path.
    private func createSchemeDir(in sourceRoot: String, container: String,
                                  schemeName: String, content: String) throws {
        let dir = (((sourceRoot as NSString).appendingPathComponent(container) as NSString)
            .appendingPathComponent("xcshareddata/xcschemes"))
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent("\(schemeName).xcscheme")
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
