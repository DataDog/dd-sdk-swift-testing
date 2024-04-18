/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#pragma once
#include <mach-o/dyld.h>

#ifdef __cplusplus
extern "C" {
#endif

void* _Nullable FindSymbolInImage(const char* _Nonnull symbol, const struct mach_header* _Nonnull image, intptr_t slide);
void ProfileResetCounters(void* _Nonnull beginCounters, void* _Nonnull endCounters, void* _Nonnull beginData, void* _Nonnull endData);

#ifdef __cplusplus
}
#endif
