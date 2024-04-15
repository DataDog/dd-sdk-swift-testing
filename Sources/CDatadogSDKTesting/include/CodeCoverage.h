/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

const char* _Nonnull LLVMCoverageInfoForProfile(const char* _Nonnull prof_data, const char* _Nonnull const* _Nullable images, unsigned int image_count);

#ifdef __cplusplus
}
#endif
