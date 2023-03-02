/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

// Annotation for specifying a calling convention of
// a runtime function. It should be used with declarations
// of runtime functions like this:
// void runtime_function_name() SWIFT_CC(swift)
#define SWIFT_CC(CC) SWIFT_CC_ ## CC

// SWIFT_CC(c) is the C calling convention.
#define SWIFT_CC_c

#define SWIFT_CC_swift __attribute__((swiftcall))

typedef int __int32_t;
typedef __int32_t __darwin_pid_t;
typedef __darwin_pid_t pid_t;
typedef unsigned short __uint16_t;
typedef __uint16_t __darwin_mode_t;             /* [???] Some file attributes */
typedef __darwin_mode_t mode_t;



typedef  void *posix_spawnattr_t;
typedef  void *posix_spawn_file_actions_t;

int posix_spawn_file_actions_init(posix_spawn_file_actions_t *);
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *);
int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *, int);
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *, int, int);
int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t * __restrict, int, const char * __restrict, int, mode_t);

int     posix_spawn(pid_t * __restrict, const char * __restrict,
                    const posix_spawn_file_actions_t *,
                    const posix_spawnattr_t * __restrict,
                    char *const __argv[__restrict],
                    char *const __envp[__restrict]);

SWIFT_CC(swift)
int _stdlib_posix_spawn_file_actions_init(posix_spawn_file_actions_t *file_actions) {
	return posix_spawn_file_actions_init(file_actions);
}

SWIFT_CC(swift)
int _stdlib_posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *file_actions) {
	return posix_spawn_file_actions_destroy(file_actions);
}

SWIFT_CC(swift)
int _stdlib_posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *file_actions, int filedes) {
	return posix_spawn_file_actions_addclose(file_actions, filedes);
}

SWIFT_CC(swift)
int _stdlib_posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *file_actions, int filedes, int newfiledes) {
	return posix_spawn_file_actions_adddup2(file_actions, filedes, newfiledes);
}

SWIFT_CC(swift)
int _stdlib_posix_spawn_file_actions_addopen(posix_spawn_file_actions_t * file_actions, int filedes, const char * path, int oflag, mode_t mode) {
	return posix_spawn_file_actions_addopen(file_actions, filedes, path, oflag, mode);
}

SWIFT_CC(swift)
int _stdlib_posix_spawn(pid_t *__restrict pid, const char * __restrict path,
                        const posix_spawn_file_actions_t *file_actions,
                        const posix_spawnattr_t *__restrict attrp,
                        char *const argv[__restrict],
                        char *const envp[__restrict]) {
	return posix_spawn(pid, path, file_actions, attrp, argv, envp);
}
