/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

struct CommitData: Codable {
    var id: String
    var type = "commit"
}

struct CommitResponseFormat: Codable, JSONable {
    var data: [CommitData]
}

struct CommitRequesFormat: Codable, JSONable {
    var meta: Meta
    var data: [CommitData]

    struct Meta: Codable {
        var repositoryURL: String

        enum CodingKeys: String, CodingKey {
            case repositoryURL = "repository_url"
        }
    }

    init(repositoryURL: String, commits: [String]) {
        self.meta = Meta(repositoryURL: repositoryURL)
        self.data = commits.map {
            CommitData(id: $0)
        }
    }
}
