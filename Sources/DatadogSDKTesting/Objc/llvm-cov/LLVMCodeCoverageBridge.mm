/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

#include <string>
#include <vector>

#import <DatadogSDKTesting/LLVMCodeCoverageBridge.h>


std::string getCoverage(std::string profdata, std::vector<std::string> covFilenames);

/// Implementation of LLVMBridge
@implementation LLVMCodeCoverageBridge

+ (nonnull NSString *)coverageInfoForProfile:(nonnull NSString*)profData
                                      images:(nonnull NSArray*)objectArray {

    __block std::vector<std::string> vectorList;
    vectorList.reserve([objectArray count]);
    [objectArray enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        vectorList.push_back([obj cStringUsingEncoding:NSUTF8StringEncoding]);
    }];

    std::string coverage = getCoverage([profData cStringUsingEncoding:NSUTF8StringEncoding], vectorList);

    return [NSString stringWithUTF8String:coverage.c_str()];
}

@end /* implementation LLVMCodeCoverageBridge */
