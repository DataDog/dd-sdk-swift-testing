/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

/// It stores information about loaded mach images
struct MachOImage {
    var header: UnsafePointer<mach_header>?
    var slide: Int
    var path: String
}

struct ProfileInfoImage {
    let name: String
    let writeFileFuncPtr: UnsafeMutableRawPointer
    let beginCountersFuncPtr: UnsafeMutableRawPointer
    let endCountersFuncPtr: UnsafeMutableRawPointer
    let beginDataFuncPtr: UnsafeMutableRawPointer
    let endDataFuncPtr: UnsafeMutableRawPointer
    let profileInitializeFileFuncPtr: UnsafeMutableRawPointer?
}

struct BinaryImages {
    private static var instance = BinaryImages()

    private var imageAddresses: [String: MachOImage]
    private var profileImages: [ProfileInfoImage]

    private init() {
        /// User library addresses are randomized each time an app is run, create a map to locate library addresses by name,
        /// system libraries are not so address returned is 0
        imageAddresses = [String: MachOImage]()
        profileImages = [ProfileInfoImage]()
        let numImages = _dyld_image_count()
        for i in 0 ..< numImages {
            guard let header = _dyld_get_image_header(i) else {
                continue
            }
            let path = String(cString: _dyld_get_image_name(i))
            let name = URL(fileURLWithPath: path).lastPathComponent
            let slide = _dyld_get_image_vmaddr_slide(i)
            if slide != 0 {
                imageAddresses[name] = MachOImage(header: header, slide: slide, path: path)
            } else {
                // Its a system library, use library Address as slide value instead of 0
                imageAddresses[name] = MachOImage(header: header, slide: Int(bitPattern: header), path: path)
            }

            if let write_file_symbol = FindSymbolInImage("___llvm_profile_write_file", header, slide),
               let begin_counters_symbol = FindSymbolInImage("___llvm_profile_begin_counters", header, slide),
               let end_counters_symbol = FindSymbolInImage("___llvm_profile_end_counters", header, slide),
               let begin_data_symbol = FindSymbolInImage("___llvm_profile_begin_data", header, slide),
               let end_data_symbol = FindSymbolInImage("___llvm_profile_end_data", header, slide),
               let profile_initialize_symbol = FindSymbolInImage("___llvm_profile_initialize", header, slide)
            {
                let profileImage = ProfileInfoImage(name: name,
                                                    writeFileFuncPtr: write_file_symbol,
                                                    beginCountersFuncPtr: begin_counters_symbol,
                                                    endCountersFuncPtr: end_counters_symbol,
                                                    beginDataFuncPtr: begin_data_symbol,
                                                    endDataFuncPtr: end_data_symbol,
                                                    profileInitializeFileFuncPtr: profile_initialize_symbol)
                profileImages.append(profileImage)
            }
        }
    }

    /// Structure to store all loaded libraries and images in the process
    static var imageAddresses: [String: MachOImage] = {
        BinaryImages.instance.imageAddresses
    }()

    static var profileImages: [ProfileInfoImage] = {
        BinaryImages.instance.profileImages
    }()
}
