/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#include "include/AutoLoad.h"

// This code will run when the framework is loaded in memory and before the application
// or tests start.
// Reference: https://developer.apple.com/documentation/objectivec/nsobject/1418815-load
__attribute__((constructor)) void AutoLoadHandler(void) {
    __AutoLoadHook();
}

// This code will run when the framework is unloaded from memory.
// Reference: https://developer.apple.com/documentation/objectivec/nsobject/1418815-load
__attribute__((destructor)) void AutoUnloadHandler(void) {
    __AutoUnloadHook();
}
