/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach_init.h>
#import <mach/task.h>   // for mach_ports_register

// This code will run when the framework is loaded in memory and before the application
// or tests start.
// Reference: https://developer.apple.com/documentation/objectivec/nsobject/1418815-load
__attribute__((constructor)) static void initialize_FrameworkLoadHandler() {
	Class frameworkLoadHandlerClass = objc_getClass("DatadogSDKTesting.FrameworkLoadHandler");
	SEL handleLoadSelector = NSSelectorFromString(@"handleLoad");
	NSMethodSignature *methodSignature = [frameworkLoadHandlerClass methodSignatureForSelector:handleLoadSelector];
	NSInvocation *myInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
	[myInvocation setTarget:frameworkLoadHandlerClass];
	[myInvocation setSelector:handleLoadSelector];
	[myInvocation invoke];
}
