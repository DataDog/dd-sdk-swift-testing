/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#ifdef __INT32_TYPE__
typedef __INT32_TYPE__  dd_pid_t;
#endif

#ifdef __INT16_TYPE__
typedef __UINT16_TYPE__ dd_mode_t;
#endif

typedef  void *posix_spawnattr_t;
typedef  void *posix_spawn_file_actions_t;

int dd_posix_spawn_file_actions_init(posix_spawn_file_actions_t *actions);
int dd_posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *actions);
int dd_posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *actions, int fd);
int dd_posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *actions, int fd, int newfd);
int dd_posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *actions, int fd, const char *path, int oflag, dd_mode_t mode);
int dd_posix_spawn(dd_pid_t *pid, const char *file,
                   const posix_spawn_file_actions_t *actions,
                   const posix_spawnattr_t *attrp,
                   char *const argv[],
                   char *const envp[]);

#ifdef __cplusplus
}
#endif
