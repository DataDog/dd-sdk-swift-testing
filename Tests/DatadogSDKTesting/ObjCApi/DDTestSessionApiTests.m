/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */


#import <XCTest/XCTest.h>
@import DatadogSDKTesting;

@interface DDTestModuleApiTests : XCTestCase

@end

@implementation DDTestModuleApiTests

- (void)testApiIsAccessible{
    DDTestModule *module = [DDTestModule startWithBundleName:@"ManualObjcTestingModule" startTime:nil];
    DDTestSuite *suite = [module suiteStartWithName:@"ManualObjcTestingSuite" startTime:nil];
    DDTest *test = [suite testStartWithName:@"ManualObjcTestingTest" startTime:nil];
    [test setTagWithKey:@"key" value:@"value"];
    [test setErrorInfoWithType:@"errorType" message:@"error Message" callstack:nil];
    [test endWithStatus:DDTestStatusPass endTime:nil];
    [suite endWithTime:nil];
    [module endWithTime:nil];
}

@end
