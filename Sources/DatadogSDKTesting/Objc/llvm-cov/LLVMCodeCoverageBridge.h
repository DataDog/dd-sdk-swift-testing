/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

#ifndef LLVMCodeCoverageBridge_h
#define LLVMCodeCoverageBridge_h

#import <Foundation/Foundation.h>

@interface LLVMCodeCoverageBridge : NSObject

+ (nonnull NSString *)coverageInfoForProfile:(nonnull NSString*)profData
                                      images:(nonnull NSArray*)objectArray;

@end

#endif /*LLVMCodeCoverageBridge_h */
