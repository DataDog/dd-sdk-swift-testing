/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal protocol CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git)
}

extension CIEnvironmentReader {
    @inlinable
    func expand(path: String?, env: any EnvironmentReader) -> String? {
        Environment.CI.expand(path: path, home: env.get(env: "HOME"))
    }
    
    @inlinable
    func normalize(branchOrTag value: String?) -> (String?, Bool) {
        Environment.Git.normalize(branchOrTag: value)
    }
    
    @inlinable
    func normalize(branch value: String?) -> String? {
        let (branch, isTag) = normalize(branchOrTag: value)
        return branch.flatMap { isTag ? nil : $0 }
    }
    
    @inlinable
    func normalize(tag value: String?) -> String? {
        let (branch, isTag) = normalize(branchOrTag: value)
        return branch.flatMap { isTag ? $0 : nil }
    }
}
