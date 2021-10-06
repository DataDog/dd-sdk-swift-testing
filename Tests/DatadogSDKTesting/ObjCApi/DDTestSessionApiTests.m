/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */


#import <XCTest/XCTest.h>
@import DatadogSDKTesting;

@interface DDTestSessionApiTests : XCTestCase

@end

@implementation DDTestSessionApiTests

- (void)testApiIsAccessible{
    DDTestSession *session = [DDTestSession startWithBundleName:@"ManualObjcTestingSession"];
    DDTestSuite *suite = [session suiteStartWithName:@"ManualObjcTestingSuite"];
    DDTest *test = [session testStartWithName:@"ManualObjcTestingTest" suite:suite];
    [session testSetAttribute:test key:@"key" value:@"value"];
    [session testAddBenchmark:test name:@"BenchmarkName" samples:@[@1,@2,@3,@4,@5] info:nil];
    [session testSetErrorInfo:test type:@"errorType" message:@"error Message" callstack:nil];
    [session testEnd:test status:DDTestStatusPass];
    [session suiteEnd:suite];
    [session end];
}


@end
