/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

class DDFileReader {
    static fileprivate let maxLength = Int32(1024)
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        buffer = [CChar](repeating: 0, count: Int(DDFileReader.maxLength))
    }

    deinit {
        // You must close before releasing the last reference.
        precondition(self.file == nil)
    }

    let fileURL: URL

    private var file: UnsafeMutablePointer<FILE>?
    private var buffer: [CChar]

    func open() throws {
        guard let f = fopen(fileURL.path, "r") else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        self.file = f
    }

    func close() {
        if let f = self.file {
            self.file = nil
            let success = fclose(f) == 0
            assert(success)
        }
    }

    func readLine() throws -> String? {
        guard let f = self.file else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EBADF), userInfo: nil)
        }
        guard fgets(&buffer, Int32(DDFileReader.maxLength), f) != nil else {
            if feof(f) != 0 {
                return nil
            } else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
            }
        }
        return String(cString: buffer)
    }
}
