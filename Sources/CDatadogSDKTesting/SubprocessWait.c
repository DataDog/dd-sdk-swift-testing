/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

#include "include/SubprocessWait.h"
#include <stdlib.h>
#include <sys/wait.h>
#include <errno.h>
#include <string.h>

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
