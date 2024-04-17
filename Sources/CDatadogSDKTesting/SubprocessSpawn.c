/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#include "include/SubprocessSpawn.h"

extern int posix_spawn_file_actions_init(posix_spawn_file_actions_t *);
extern int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *);
extern int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *, int);
extern int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *, int, int);
extern int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t * __restrict, int, const char * __restrict, int, dd_mode_t);

extern int posix_spawn(dd_pid_t * __restrict, const char * __restrict,
                       const posix_spawn_file_actions_t *,
                       const posix_spawnattr_t * __restrict,
                       char *const __argv[__restrict],
                       char *const __envp[__restrict]);

int dd_posix_spawn_file_actions_init(posix_spawn_file_actions_t *actions) {
    return posix_spawn_file_actions_init(actions);
}

int dd_posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *actions) {
    return posix_spawn_file_actions_destroy(actions);
}

int dd_posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *actions, int fd) {
    return posix_spawn_file_actions_addclose(actions, fd);
}

int dd_posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *actions, int fd, int newfd) {
    return posix_spawn_file_actions_adddup2(actions, fd, newfd);
}

int dd_posix_spawn_file_actions_addopen(posix_spawn_file_actions_t * __restrict actions, int fd,
                                        const char * __restrict file, int oflag, dd_mode_t mode)
{
    return posix_spawn_file_actions_addopen(actions, fd, file, oflag, mode);
}

int dd_posix_spawn(dd_pid_t * __restrict pid, const char * __restrict command,
                   const posix_spawn_file_actions_t *actions,
                   const posix_spawnattr_t * __restrict attrp,
                   char *const argv[__restrict],
                   char *const envp[__restrict])
{
    return posix_spawn(pid, command, actions, attrp, argv, envp);
}
