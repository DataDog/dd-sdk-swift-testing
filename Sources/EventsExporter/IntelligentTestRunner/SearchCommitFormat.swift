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

struct CommitResponseFormat: Codable {
    var data: [CommitData]
}

struct CommitRequesFormat: Codable {
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

extension CommitRequesFormat {
    var jsonData: Data? {
        return try? JSONEncoder().encode(self)
    }

    var json: String? {
        guard let data = self.jsonData else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
