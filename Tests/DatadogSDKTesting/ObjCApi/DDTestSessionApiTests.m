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
    DDTestSession *session = [DDTestSession startWithBundleName:@"ManualObjcTestingSession" startTime:nil];
    DDTestSuite *suite = [session suiteStartWithName:@"ManualObjcTestingSuite" startTime:nil];
    DDTest *test = [suite testStartWithName:@"ManualObjcTestingTest" startTime:nil];
    [test setTagWithKey:@"key" value:@"value"];
    [test setErrorInfoWithType:@"errorType" message:@"error Message" callstack:nil];
    [test endWithStatus:DDTestStatusPass endTime:nil];
    [suite endWithTime:nil];
    [session endWithTime:nil];
}


@end
