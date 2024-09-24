/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

internal struct TeamcityCIEnvironmentReader: CIEnvironmentReader {
    func isActive(env: any EnvironmentReader) -> Bool { env["TEAMCITY_VERSION"] ?? "" != "" }
    
    func read(env: any EnvironmentReader) -> (ci: Environment.CI, git: Environment.Git) {
        (
            ci: .init(
                provider: "teamcity",
                jobName: env["TEAMCITY_BUILDCONF_NAME"],
                jobURL: env["BUILD_URL"]
            ),
            git: .init()
        )
    }
}
