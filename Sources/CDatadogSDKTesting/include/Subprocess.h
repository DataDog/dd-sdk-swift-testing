/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <sys/types.h>
#include <sys/signal.h>
#include <stdbool.h>

typedef  void *posix_spawnattr_t;
typedef  void *posix_spawn_file_actions_t;

int dd_posix_spawn_file_actions_init(posix_spawn_file_actions_t *);
int dd_posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *);
int dd_posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *, int);
int dd_posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *, int, int);
int dd_posix_spawn_file_actions_addopen(posix_spawn_file_actions_t * __restrict, int, const char * __restrict, int, mode_t);
int dd_posix_spawn(pid_t * __restrict, const char * __restrict,
                   const posix_spawn_file_actions_t *,
                   const posix_spawnattr_t * __restrict,
                   char *const __argv[__restrict],
                   char *const __envp[__restrict]);

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
