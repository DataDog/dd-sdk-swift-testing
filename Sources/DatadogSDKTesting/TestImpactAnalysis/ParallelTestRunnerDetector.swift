/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Detects whether test parallelization is disabled for the running test target.
/// Used by `Environment` to automatically enable Swift Testing TIA when tests are
/// confirmed to run serially.
enum ParallelTestRunnerDetector {

    /// Returns `true` when test parallelization is detected as disabled for `targetName`.
    ///
    /// Detection strategy (in priority order):
    /// 1. **Xcode with test plan** (`XCODE_TEST_PLAN_NAME` set): reads `parallelizable` from the
    ///    `.xctestplan` file for the target whose `name` matches `targetName`.
    /// 2. **Xcode without test plan** (`XCODE_SCHEME_NAME` set, no `XCODE_TEST_PLAN_NAME`): reads
    ///    `parallelizable` from the `.xcscheme` `TestableReference` whose `BlueprintName` matches
    ///    `targetName`.
    /// 3. **`swift test`** (neither env var set): checks `ProcessInfo.processInfo.arguments`
    ///    for `--no-parallel`.
    ///
    /// When `targetName` is `nil` (unknown bundle), detection falls back to checking whether
    /// *any* configured target has parallelization disabled.
    static func isParallelizationDisabled(env: EnvironmentReader, sourceRoot: String?,
                                          targetName: String?) -> Bool {
        let testPlanName: String? = env.get(env: "XCODE_TEST_PLAN_NAME")
        let schemeName: String? = env.get(env: "XCODE_SCHEME_NAME")

        if let testPlanName {
            guard let sourceRoot else { return false }
            return checkTestPlan(named: testPlanName, sourceRoot: sourceRoot,
                                 schemeName: schemeName, targetName: targetName) ?? false
        }

        if let schemeName {
            guard let sourceRoot else { return false }
            return checkScheme(named: schemeName, sourceRoot: sourceRoot,
                               targetName: targetName) ?? false
        }

        return ProcessInfo.processInfo.arguments.contains("--no-parallel")
    }

    // MARK: - Test Plan

    private static func checkTestPlan(named name: String, sourceRoot: String,
                                      schemeName: String?, targetName: String?) -> Bool? {
        guard let planPath = resolvePlanPath(named: name, sourceRoot: sourceRoot,
                                            schemeName: schemeName),
              let data = FileManager.default.contents(atPath: planPath) else { return nil }
        return isTestPlanNonParallel(data: data, targetName: targetName)
    }

    private static func resolvePlanPath(named name: String, sourceRoot: String,
                                        schemeName: String?) -> String? {
        if let schemeName,
           let schemeURL = findSchemeFile(named: schemeName, in: sourceRoot) {
            let parser = XCSchemeParser()
            if let scheme = parser.parse(url: schemeURL),
               let path = scheme.testPlanPath(named: name, sourceRoot: sourceRoot) {
                return path
            }
        }
        return findFile(named: "\(name).xctestplan", in: sourceRoot, maxDepth: 5)
    }

    /// Checks whether the test plan data has parallelization disabled.
    ///
    /// When `targetName` is supplied the check is scoped to the matching target entry:
    /// - target found with `parallelizable: false` → `true`
    /// - target found without the key or `parallelizable: true` → `false`
    /// - target not found → `nil` (can't determine)
    ///
    /// When `targetName` is `nil` any target with `parallelizable: false` returns `true`.
    static func isTestPlanNonParallel(data: Data, targetName: String?) -> Bool? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let testTargets = json["testTargets"] as? [[String: Any]],
              !testTargets.isEmpty else { return nil }

        if let targetName {
            guard let entry = testTargets.first(where: {
                ($0["target"] as? [String: Any])?["name"] as? String == targetName
            }) else { return nil }
            return (entry["parallelizable"] as? Bool) == false
        }

        return testTargets.contains { ($0["parallelizable"] as? Bool) == false }
    }

    // MARK: - Scheme (no test plan)

    private static func checkScheme(named name: String, sourceRoot: String,
                                    targetName: String?) -> Bool? {
        guard let schemeURL = findSchemeFile(named: name, in: sourceRoot) else { return nil }
        let parser = XCSchemeParser()
        guard let scheme = parser.parse(url: schemeURL) else { return nil }
        guard !scheme.hasTestPlans, !scheme.testableReferences.isEmpty else { return nil }

        if let targetName {
            guard let ref = scheme.testableReferences.first(where: {
                $0.targetName == targetName
            }) else { return nil }
            return ref.isNonParallel
        }

        return scheme.testableReferences.contains { $0.isNonParallel }
    }

    // MARK: - File utilities

    /// Finds `<name>.xcscheme` inside any `*.xcodeproj` or `*.xcworkspace` located
    /// directly under `sourceRoot`.
    static func findSchemeFile(named name: String, in sourceRoot: String) -> URL? {
        let fm = FileManager.default
        let fileName = "\(name).xcscheme"
        guard let items = try? fm.contentsOfDirectory(atPath: sourceRoot) else { return nil }
        for item in items where item.hasSuffix(".xcodeproj") || item.hasSuffix(".xcworkspace") {
            let schemesDir = (((sourceRoot as NSString).appendingPathComponent(item) as NSString)
                .appendingPathComponent("xcshareddata/xcschemes"))
            let schemePath = (schemesDir as NSString).appendingPathComponent(fileName)
            if fm.fileExists(atPath: schemePath) {
                return URL(fileURLWithPath: schemePath)
            }
        }
        return nil
    }

    /// Recursively searches `directory` (up to `maxDepth` levels) for a file named `fileName`.
    /// Hidden entries and Xcode/build artefact directories are skipped.
    static func findFile(named fileName: String, in directory: String, maxDepth: Int) -> String? {
        guard maxDepth >= 0 else { return nil }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else { return nil }
        for item in contents {
            let path = (directory as NSString).appendingPathComponent(item)
            if item == fileName { return path }
            guard maxDepth > 0,
                  !item.hasPrefix("."),
                  !item.hasSuffix(".xcodeproj"),
                  !item.hasSuffix(".xcworkspace"),
                  item != "DerivedData", item != "build", item != ".build" else { continue }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue,
               let found = findFile(named: fileName, in: path, maxDepth: maxDepth - 1) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Xcscheme XML parser

private final class XCSchemeParser: NSObject, XMLParserDelegate {

    struct Scheme {
        struct TestableRef {
            /// `true` when the XML attribute `parallelizable = "NO"`.
            let isNonParallel: Bool
            /// The `BlueprintName` of the nested `BuildableReference` element.
            let targetName: String?
        }

        var testPlanReferences: [String] = []
        var testableReferences: [TestableRef] = []

        var hasTestPlans: Bool { !testPlanReferences.isEmpty }

        /// Resolves the file-system path to the test plan named `name` using the
        /// `container:`-relative reference stored in the scheme.
        func testPlanPath(named name: String, sourceRoot: String) -> String? {
            let suffix = "\(name).xctestplan"
            guard let reference = testPlanReferences.first(where: { $0.hasSuffix(suffix) }) else {
                return nil
            }
            let relative = reference.replacingOccurrences(of: "container:", with: "")
            return (sourceRoot as NSString).appendingPathComponent(relative)
        }
    }

    // Mutable snapshot collected while parsing a single <TestableReference> element.
    private struct PendingRef {
        var isNonParallel: Bool
        var targetName: String? = nil
    }

    private var scheme = Scheme()
    private var inTestAction = false
    private var pendingRef: PendingRef? = nil

    func parse(url: URL) -> Scheme? {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        parser.delegate = self
        return parser.parse() ? scheme : nil
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        switch elementName {
        case "TestAction":
            inTestAction = true
        case "TestPlanReference" where inTestAction:
            if let ref = attributeDict["reference"] {
                scheme.testPlanReferences.append(ref)
            }
        case "TestableReference" where inTestAction:
            let isNonParallel = attributeDict["parallelizable"].map {
                $0.uppercased() == "NO"
            } ?? false
            pendingRef = PendingRef(isNonParallel: isNonParallel)
        case "BuildableReference" where pendingRef != nil:
            pendingRef?.targetName = attributeDict["BlueprintName"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "TestableReference" where inTestAction:
            if let ref = pendingRef {
                scheme.testableReferences.append(
                    .init(isNonParallel: ref.isNonParallel, targetName: ref.targetName)
                )
            }
            pendingRef = nil
        case "TestAction":
            inTestAction = false
        default:
            break
        }
    }
}
