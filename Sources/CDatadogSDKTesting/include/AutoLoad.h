/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// This hook will be called by library.
// Implement it in your Swift code as @_cdecl
void __AutoLoadHook(void);

// This hook will be called by library.
// Implement it in your Swift code as @_cdecl
void __AutoUnloadHook(void);

// Never call this methods directly. They will be called by system dynamic loader
extern void AutoLoadHandler(void);
extern void AutoUnloadHandler(void);

#ifdef __cplusplus
}
#endif
