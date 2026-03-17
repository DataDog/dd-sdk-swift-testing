//
//  SwiftTestingObserver.swift
//  DatadogSDKTesting
//
//  Created by Yehor Popovych on 13/03/2026.
//
import Foundation

protocol SessionProvider: Sendable {
    func sharedSession() async throws -> Session
}

protocol SwiftTestingTest {
    var name: String { get }
    var module: String { get }
    var isSuite: Bool { get }
    var suite: String { get }
}

protocol SwiftTestingTestRun: SwiftTestingTest {
    var isParametrised: Bool { get }
    // This is a private API for now in the swift testing
    // var parameters: [(name: String, value: String)] { get }
}

enum SwiftTestingTestStatus: Equatable, Hashable, Sendable {
    case skipped(reason: String)
    case failed
    case passed
}

protocol SwiftTestingObserverType: Sendable {
    func register(test: some SwiftTestingTest) async throws
    func willRun(testRun test: some SwiftTestingTestRun) async throws -> RetryGroupConfiguration
    func shouldSuppressError(testRun test: some SwiftTestingTestRun) -> Bool
    func didRun(testRun test: some SwiftTestingTestRun, status: SwiftTestingTestStatus) async throws -> RetryStatus
}

final class SwiftTestingObserver: SwiftTestingObserverType {
    private let _provider: SessionProvider
    
    init(provider: SessionProvider) {
        self._provider = provider
    }
    
    func register(test: some SwiftTestingTest) async throws {
        fatalError("not implemented")
    }
    
    func willRun(testRun test: some SwiftTestingTestRun) async throws -> RetryGroupConfiguration {
        fatalError("not implemented")
    }
    
    func shouldSuppressError(testRun test: some SwiftTestingTestRun) -> Bool {
        fatalError("not implemented")
    }
    
    func didRun(testRun test: some SwiftTestingTestRun, status: SwiftTestingTestStatus) async throws -> RetryStatus {
        fatalError("not implemented")
    }
}
