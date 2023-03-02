/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/// This is the method that sanitizers call to print messages, we capture it and store with our Test module. This is called asynchornously.
void __sanitizer_on_print(const char *str) {
    Class sanitizerHelperClass = objc_getClass("DatadogSDKTesting.SanitizerHelper");
    SEL logSanitizerMessageSelector = NSSelectorFromString(@"logSanitizerMessage:");
    NSMethodSignature *methodSignature = [sanitizerHelperClass methodSignatureForSelector:logSanitizerMessageSelector];
    NSInvocation *myInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    [myInvocation setSelector:logSanitizerMessageSelector];
    [myInvocation setTarget:sanitizerHelperClass];
    NSString *string = [NSString stringWithCString:str encoding:NSUTF8StringEncoding];
    [myInvocation setArgument:&string atIndex:2];
    [myInvocation invoke];
}
