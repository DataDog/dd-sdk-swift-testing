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

    static func getCoverageJson(profdataFile: URL) -> String {
        let input = profdataFile.path
        let binaryImagePaths = BinaryImages.profileImages.map{ return $0.path }
        let binariesPath =  binaryImagePaths.joined(separator: " -object ")

        let commandToRun = #"xcrun llvm-cov export -skip-functions -skip-expansions -instr-profile "\#(input)" -object \#(binariesPath)"#

        return Spawn.commandWithResult(commandToRun)
    }
}
