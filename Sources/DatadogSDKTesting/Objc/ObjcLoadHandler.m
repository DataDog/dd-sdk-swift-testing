/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

__attribute__((constructor)) static void initialize_FrameworkLoadHandler() {
    Class frameworkLoadHandlerClass = objc_getClass("DatadogSDKTesting.FrameworkLoadHandler");
    SEL handleLoadSelector = NSSelectorFromString(@"handleLoad");
    NSMethodSignature *methodSignature = [frameworkLoadHandlerClass methodSignatureForSelector:handleLoadSelector];
    NSInvocation *myInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    [myInvocation setTarget:frameworkLoadHandlerClass];
    [myInvocation setSelector:handleLoadSelector];
    [myInvocation invoke];
}
