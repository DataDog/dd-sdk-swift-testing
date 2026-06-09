/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

internal import EventsExporter

extension Environment.Platform {
    var device: Device {
        Device(name: deviceName,
               model: deviceModel,
               osName: osName,
               osVersion: osVersion,
               osArchitecture: osArchitecture)
    }
    
    var kernelInfo: KernelInfo {
        KernelInfo(sysname: sysname,
                   release: kernelRelease,
                   version: kernelVersion,
                   machine: machine)
    }
}
