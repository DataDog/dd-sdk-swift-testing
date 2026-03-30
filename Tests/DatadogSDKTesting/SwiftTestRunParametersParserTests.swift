/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSDKTesting

final class SwiftTestRunParametersParserTests: XCTestCase {
    private typealias Run = DatadogSwiftTestingScopeProvider.SwiftTestRun

    // MARK: - No arguments

    func testNonParameterizedDescriptionReturnsEmpty() {
        // A non-parameterized case has no Argument tokens in the description.
        let description = "Case(_kind: ..._Kind.single, body: (Function))"
        XCTAssertTrue(Run.parseSwiftTestCaseParameters(from: description).isEmpty)
    }

    func testEmptyStringReturnsEmpty() {
        XCTAssertTrue(Run.parseSwiftTestCaseParameters(from: "").isEmpty)
    }

    // MARK: - Single argument, secondName nil

    func testSingleIntArgument_secondNameNil() {
        let description = makeDescription(arguments: [
            makeArgument(value: "2", bytes: "50",
                         index: 0, firstName: "p1", secondName: nil, typeInfo: "Swift.Int")
        ])
        let result = Run.parseSwiftTestCaseParameters(from: description)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "p1")
        XCTAssertEqual(result[0].value, "2")
    }

    func testSingleStringArgument_secondNameNil() {
        // String values appear with surrounding quotes in the description.
        let description = makeDescription(arguments: [
            makeArgument(value: #""hello""#, bytes: "104, 101, 108, 108, 111",
                         index: 0, firstName: "label", secondName: nil, typeInfo: "Swift.String")
        ])
        let result = Run.parseSwiftTestCaseParameters(from: description)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "label")
        XCTAssertEqual(result[0].value, #""hello""#)
    }

    // MARK: - Single argument, secondName present

    func testSingleArgument_secondNamePresent() {
        let description = makeDescription(arguments: [
            makeArgument(value: "42", bytes: "52, 50",
                         index: 0, firstName: "for", secondName: "count", typeInfo: "Swift.Int")
        ])
        let result = Run.parseSwiftTestCaseParameters(from: description)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "for count")
        XCTAssertEqual(result[0].value, "42")
    }

    // MARK: - Multiple arguments

    func testTwoArguments_bothSecondNameNil() {
        let description = makeDescription(arguments: [
            makeArgument(value: "2", bytes: "50",
                         index: 0, firstName: "p1", secondName: nil, typeInfo: "Swift.Int"),
            makeArgument(value: #""2""#, bytes: "34, 50, 34",
                         index: 1, firstName: "p2", secondName: nil, typeInfo: "Swift.String")
        ])
        let result = Run.parseSwiftTestCaseParameters(from: description)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "p1")
        XCTAssertEqual(result[0].value, "2")
        XCTAssertEqual(result[1].name, "p2")
        XCTAssertEqual(result[1].value, #""2""#)
    }

    func testTwoArguments_mixedSecondName() {
        let description = makeDescription(arguments: [
            makeArgument(value: "1", bytes: "49",
                         index: 0, firstName: "for", secondName: "x", typeInfo: "Swift.Int"),
            makeArgument(value: #""abc""#, bytes: "97, 98, 99",
                         index: 1, firstName: "p2", secondName: nil, typeInfo: "Swift.String")
        ])
        let result = Run.parseSwiftTestCaseParameters(from: description)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "for x")
        XCTAssertEqual(result[0].value, "1")
        XCTAssertEqual(result[1].name, "p2")
        XCTAssertEqual(result[1].value, #""abc""#)
    }

    // MARK: - Full example from spec

    func testFullSpecExample() {
        // The description from the original specification comment.
        let description = #"Case(_kind: Testing.Test.Case.(unknown context at $101efe768)._Kind.parameterized(arguments: [Testing.Test.Case.Argument(value: 2, id: Testing.Test.Case.Argument.ID(bytes: [50]), parameter: Testing.Test.Parameter(index: 0, firstName: "_", secondName: "p1", typeInfo: Swift.Int)), Testing.Test.Case.Argument(value: "2", id: Testing.Test.Case.Argument.ID(bytes: [34, 50, 34]), parameter: Testing.Test.Parameter(index: 1, firstName: "str", secondName: "p2", typeInfo: Swift.String))], discriminator: 0, isStable: true), body: (Function))"#
        let result = Run.parseSwiftTestCaseParameters(from: description)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "_ p1")
        XCTAssertEqual(result[0].value, "2")
        XCTAssertEqual(result[1].name, "str p2")
        XCTAssertEqual(result[1].value, #""2""#)
    }

    // MARK: - Helpers

    private func makeArgument(value: String, bytes: String,
                               index: Int, firstName: String, secondName: String?,
                               typeInfo: String) -> String
    {
        let second = secondName.map { #""\#($0)""# } ?? "nil"
        return #"Testing.Test.Case.Argument(value: \#(value), id: Testing.Test.Case.Argument.ID(bytes: [\#(bytes)]), parameter: Testing.Test.Parameter(index: \#(index), firstName: "\#(firstName)", secondName: \#(second), typeInfo: \#(typeInfo)))"#
    }

    private func makeDescription(arguments: [String]) -> String {
        let joined = arguments.joined(separator: ", ")
        return #"Case(_kind: Testing.Test.Case.(unknown context at $0)._Kind.parameterized(arguments: [\#(joined)], discriminator: 0, isStable: true), body: (Function))"#
    }
}
