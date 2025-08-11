/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import MachO
internal import CDatadogSDKTesting

/// It stores information about loaded mach images
struct MachOImage {
    var header: UnsafePointer<mach_header>
    var slide: Int
    var path: URL
}

struct BinaryImages {
    private static var instance = BinaryImages()

    private var imageAddresses: [String: MachOImage]

    private init() {
        /// User library addresses are randomized each time an app is run, create a map to locate library addresses by name,
        /// system libraries are not so address returned is 0
        imageAddresses = [String: MachOImage]()
        let numImages = _dyld_image_count()
        for i in 0 ..< numImages {
            guard let header = _dyld_get_image_header(i) else {
                continue
            }
            let path = URL(fileURLWithPath: String(cString: _dyld_get_image_name(i)), isDirectory: false)
            let name = path.lastPathComponent
            let slide = _dyld_get_image_vmaddr_slide(i)
            
            if slide != 0 {
                imageAddresses[name] = MachOImage(header: header, slide: slide, path: path)
            } else {
                // Its a system library, use library Address as slide value instead of 0
                imageAddresses[name] = MachOImage(header: header, slide: Int(bitPattern: header), path: path)
            }
        }
    }

    /// Structure to store all loaded libraries and images in the process
    static var imageAddresses: [String: MachOImage] = {
        BinaryImages.instance.imageAddresses
    }()
}
