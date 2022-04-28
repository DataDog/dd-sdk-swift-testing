/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

struct LLVMCoverageFormat {
    struct Datum {
        let files: [File]
    }

    struct File {
        let filename: String
        let segments: [Segment]
    }

    struct Segment {
        let line: Int
        let column: Int
        let count: Int
    }

    let data: [Datum]
}

extension LLVMCoverageFormat {
    init(data: Data) throws {
        // Use ObjC parser to avoid reserving memory, and parse only really needed bytes. Keep
        // the ObjC types as long as possible to avoid extra conversions
        guard let object = try JSONSerialization.jsonObject(with: data) as? NSDictionary,
              let data = object["data"] as? NSArray,
              let firstElement = data.firstObject as? NSDictionary,
              let jsonFiles = firstElement["files"] as? [NSDictionary]
        else {
            self.data = [Datum]()
            return
        }

        let files: [File] = jsonFiles.filter { file in
            let segments = file["segments"] as? [NSArray]
            return segments?.contains { ($0[2] as! NSNumber).intValue != 0 } ?? false
        }.map { file in
            let segments = file["segments"] as! [NSArray]
            return File(filename: file["filename"] as! String,
                        segments: segments.map { segment in
                            Segment(line: (segment[0] as! NSNumber).intValue,
                                    column: (segment[1] as! NSNumber).intValue,
                                    count: (segment[2] as! NSNumber).intValue)
                        })
        }

        if files.count > 0 {
            self.data = [Datum(files: files)]
        } else {
            self.data = [Datum]()
        }
    }

    init?(_ json: String, using encoding: String.Encoding = .utf8) {
        guard let data = json.data(using: encoding) else { return nil }
        try? self.init(data: data)
    }

    init?(fromURL url: URL) {
        guard let data = try? Data(contentsOf: url, options: Data.ReadingOptions.mappedIfSafe) else { return nil }
        do {
            try self.init(data: data)
        } catch {
            Log.print("[process-coverage] Unexpected error in File: \n\(url.path)\nError: \(error)\n")
            return nil
        }
    }
}
