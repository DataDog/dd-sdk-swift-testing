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

    static func getDatadogCoverage(profdataFile: URL, testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64, workspacePath: String?, binaryImagePaths: [String]) -> DDCoverageFormat? {
#if swift(>=5.3)
        // LLVM Support is dependant on binary target, swift 5.3 is needed
        let llvmJSON = LLVMCodeCoverageBridge.coverageInfo(forProfile: profdataFile.path, images: binaryImagePaths)
        guard let llvmCov = LLVMSimpleCoverageFormat(llvmJSON) else {
            return nil
        }
        var datadogCoverage = DDCoverageFormat()
        datadogCoverage.addCoverage(llvmFormat: llvmCov, testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId, workspacePath: workspacePath)

        if datadogCoverage.coverages.count > 0 {
            return datadogCoverage
        } else {
            return nil
        }
#else
        return nil
#endif
    }
}
