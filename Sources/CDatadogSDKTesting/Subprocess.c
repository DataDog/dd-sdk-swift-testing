/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#include "include/Subprocess.h"
#include <stdlib.h>
#include <sys/wait.h>
#include <errno.h>
#include <string.h>

extern int posix_spawn_file_actions_init(posix_spawn_file_actions_t *);
extern int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *);
extern int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *, int);
extern int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *, int, int);
extern int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t * __restrict, int, const char * __restrict, int, mode_t);

extern int posix_spawn(pid_t * __restrict, const char * __restrict,
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

int dd_posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *actions, int fromfd, int tofd) {
    return posix_spawn_file_actions_adddup2(actions, fromfd, tofd);
}

int dd_posix_spawn_file_actions_addopen(posix_spawn_file_actions_t * __restrict actions, int fd,
                                        const char * __restrict path, int flags, mode_t mode)
{
    return posix_spawn_file_actions_addopen(actions, fd, path, flags, mode);
}

int dd_posix_spawn(pid_t * __restrict pid, const char * __restrict command,
                   const posix_spawn_file_actions_t *actions,
                   const posix_spawnattr_t * __restrict attrs,
                   char *const argv[__restrict],
                   char *const envp[__restrict])
{
    return posix_spawn(pid, command, actions, attrs, argv, envp);
}

run_result_t dd_wait_for_process(pid_t pid) {
    run_result_t result;
    
    while (waitid(P_PID, (id_t)pid, &result.status, WEXITED) != 0) {
        int err = errno;
        if (err != EINTR) {
            result.is_error = true;
            result.error = err;
            return result;
        }
    }
    
    result.is_error = false;
    return result;
}
