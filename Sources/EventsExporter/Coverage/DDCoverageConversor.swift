/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

struct DDCoverageConversor {
    static func generateProfData(profrawFile: URL) -> URL {
        let outputURL = profrawFile.deletingPathExtension().appendingPathExtension("profdata")
        let input = profrawFile.path
        let outputPath = outputURL.path
        let commandToRun = #"xcrun llvm-profdata merge -sparse "\#(input)" -o "\#(outputPath)""#
        Spawn.command(commandToRun)
        return outputURL
    }

    static func getCoverageJson(profdataFile: URL, testId: String, binaryImagePaths: [String]) -> URL {
        let outputURL = profdataFile.appendingPathExtension("json")
        let llvmJSON = LLVMCodeCoverageBridge.coverageInfo(forProfile: profdataFile.path, images: binaryImagePaths)
        guard let llvmCov = LLVMCoverageFormat(llvmJSON) else {
            return outputURL
        }
        let json = DDCoverageFormat(llvmFormat: llvmCov, testId: testId)
        try? json?.jsonData?.write(to: outputURL, options: .atomic)
        return outputURL
    }
}
