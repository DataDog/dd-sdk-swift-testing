/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */


#import <XCTest/XCTest.h>
@import DatadogSDKTesting;

@interface DDSessionApiTests : XCTestCase

@end

@implementation DDSessionApiTests

- (void)testApiIsAccessible {
    DDSession* session = [DDSession startWithName: @"ManualObjcTestingSession"];
    if (session == nil) {
        // `start` returns nil when the SDK can't run — no DD_API_KEY is set in the
        // unit-test plan, so this is the expected outcome here. The rest of the
        // surface below is still checked at compile time; exercising it at runtime
        // requires an API key in the environment.
        return;
    }
    DDModule *module = [session moduleStartWithName:@"ManualObjcTestingModule" startTime:nil];
    DDSuite *suite = [module suiteStartWithName:@"ManualObjcTestingSuite" startTime:nil];
    [suite testStartWithName:@"ManualObjcTestingTest" :^id(DDTest* test) {
        [test setTagWithKey:@"key" value:@"value"];
        [test setErrorInfoWithType:@"errorType" message:@"error Message" callstack:nil];
        [test setWithStatus:DDTestStatusPass];
        return nil;
    }];
    [suite endWithTime:nil];
    [module endWithTime:nil];
    [session endWithTime:nil];
}

/// Without a `DD_API_KEY` the SDK can't report anything, so `start` must return
/// nil rather than a session that silently drops everything.
- (void)testStartReturnsNilWhenSdkCannotRun {
    XCTAssertNil([DDSession startWithName: @"NoApiKeySession"]);
}

@end
