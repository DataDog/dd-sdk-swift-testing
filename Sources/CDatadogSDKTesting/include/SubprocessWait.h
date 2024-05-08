/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#pragma once

#include <stdbool.h>
#include <sys/signal.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct run_result_s {
    bool is_error;
    union {
        siginfo_t status;
        int error;
    };
} run_result_t;

run_result_t dd_wait_for_process(pid_t pid);

#ifdef __cplusplus
}
#endif
