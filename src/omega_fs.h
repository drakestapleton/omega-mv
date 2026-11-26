/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Drake Stapleton (AIEN / aien-dev)
 *
 * Descriptor-relative filesystem confinement for runtime persistence.
 */
#ifndef OMEGA_FS_H
#define OMEGA_FS_H

#include "omega_path_check.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define OMEGA_FS_PATH_MAX 4096u
#define OMEGA_FS_NAME_MAX 255u

static inline int omega_fs_dupfd(int fd) {
    return fcntl(fd, F_DUPFD_CLOEXEC, 0);
}

/* Walk a directory path one component at a time. O_NOFOLLOW therefore applies
 * to every component, not only the final one. A created directory is always
 * reopened and validated through the same path. */
static inline int omega_fs_dir_open_at(int base_fd, const char *path, int create,
                                       mode_t mode, int secure) {
    char checked[OMEGA_FS_PATH_MAX];
    if (omega_path_copy(checked, sizeof checked, path) != 0) {
        errno = EINVAL;
        return -1;
    }
#ifdef __APPLE__
    /* macOS SIP-sealed /tmp -> private/tmp and /var -> private/var symlinks in /.
     * Normalize only those OS-immutable prefixes so every component still walks
     * with O_NOFOLLOW while standard /tmp test paths work natively on macOS. */
    if (base_fd == AT_FDCWD &&
        (strcmp(checked, "/tmp") == 0 || strncmp(checked, "/tmp/", 5) == 0 ||
         strcmp(checked, "/var") == 0 || strncmp(checked, "/var/", 5) == 0)) {
        char norm[OMEGA_FS_PATH_MAX];
        if ((size_t)snprintf(norm, sizeof norm, "/private%s", checked) >= sizeof norm) {
            errno = ENAMETOOLONG;
            return -1;
        }
        memcpy(checked, norm, strlen(norm) + 1);
    }
#endif
    int absolute = checked[0] == '/';
    if (absolute && base_fd != AT_FDCWD) {
        errno = EINVAL;
        return -1;
    }
    int fd = absolute ? open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
                      : base_fd == AT_FDCWD
                            ? open(".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
                            : omega_fs_dupfd(base_fd);
    if (fd < 0) return -1;

    const char *p = checked;
    while (*p) {
        while (*p == '/') p++;
        if (!*p) break;
        const char *q = p;
        while (*q && *q != '/') q++;
        size_t n = (size_t)(q - p);
        if (n > OMEGA_FS_NAME_MAX) {
            close(fd);
            errno = ENAMETOOLONG;
            return -1;
        }
        char name[OMEGA_FS_NAME_MAX + 1];
        memcpy(name, p, n);
        name[n] = 0;
        const char *after = q;
        while (*after == '/') after++;
        int last = *after == 0;
        if (strcmp(name, ".") != 0) {
            int next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (next < 0 && errno == ENOENT && create && last) {
                if (mkdirat(fd, name, mode) != 0 && errno != EEXIST) {
                    int e = errno;
                    close(fd);
                    errno = e;
                    return -1;
                }
                next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            }
            if (next < 0) {
                int e = errno;
                close(fd);
                errno = e;
                return -1;
            }
            close(fd);
            fd = next;
        }
        p = q;
    }

    struct stat st;
    if (fstat(fd, &st) != 0) {
        int e = errno;
        close(fd);
        errno = e;
        return -1;
    }
    if (!S_ISDIR(st.st_mode) ||
        (secure && (st.st_uid != geteuid() || (st.st_mode & 022) != 0))) {
        close(fd);
        errno = EPERM;
        return -1;
    }
    return fd;
}

static inline int omega_fs_root_open(const char *path, int create, mode_t mode) {
    return omega_fs_dir_open_at(AT_FDCWD, path, create, mode, 1);
}

static inline int omega_fs_subdir_open(int root_fd, const char *path, int create, mode_t mode) {
    if (!path || path[0] == '/') {
        errno = EINVAL;
        return -1;
    }
    return omega_fs_dir_open_at(root_fd, path, create, mode, 1);
}

/* Resolve a file's parent without following any directory symlink. */
static inline int omega_fs_parent_open_at(int base_fd, const char *path, char *leaf,
                                          size_t leaf_cap) {
    char checked[OMEGA_FS_PATH_MAX];
    if (!leaf || leaf_cap == 0 || omega_path_copy(checked, sizeof checked, path) != 0 ||
        (base_fd != AT_FDCWD && checked[0] == '/')) {
        errno = EINVAL;
        return -1;
    }
    size_t len = strlen(checked);
    if (!len || checked[len - 1] == '/') {
        errno = EINVAL;
        return -1;
    }
    char *slash = strrchr(checked, '/');
    const char *name = slash ? slash + 1 : checked;
    size_t n = strlen(name);
    if (!n || n > OMEGA_FS_NAME_MAX || n + 1 > leaf_cap || strcmp(name, ".") == 0) {
        errno = n > OMEGA_FS_NAME_MAX ? ENAMETOOLONG : EINVAL;
        return -1;
    }
    memcpy(leaf, name, n + 1);
    if (!slash) return omega_fs_dir_open_at(base_fd, ".", 0, 0, 0);
    if (slash == checked) slash[1] = 0;
    else *slash = 0;
    return omega_fs_dir_open_at(base_fd, checked, 0, 0, 0);
}

static inline int omega_fs_open_regular_at(int root_fd, const char *path, int flags,
                                           mode_t mode) {
    char leaf[OMEGA_FS_NAME_MAX + 1];
    int pfd = omega_fs_parent_open_at(root_fd, path, leaf, sizeof leaf);
    if (pfd < 0) return -1;
    /* Open with O_NONBLOCK so an attacker-planted FIFO cannot stall the caller
     * before fstat rejects non-regular files. */
    int actual = (flags & ~O_TRUNC) | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK;
    int fd = openat(pfd, leaf, actual, mode);
    int saved = errno;
    close(pfd);
    if (fd < 0) {
        errno = saved;
        return -1;
    }
    struct stat st;
    if (fstat(fd, &st) != 0) {
        int e = errno;
        close(fd);
        errno = e;
        return -1;
    }
    if (!S_ISREG(st.st_mode) || st.st_uid != geteuid() || st.st_nlink != 1 ||
        (st.st_mode & 022) != 0) {
        close(fd);
        errno = EPERM;
        return -1;
    }
    if (!(flags & O_NONBLOCK)) {
        int fl = fcntl(fd, F_GETFL);
        if (fl < 0 || fcntl(fd, F_SETFL, fl & ~O_NONBLOCK) != 0) {
            saved = errno;
            close(fd);
            errno = saved;
            return -1;
        }
    }
    /* Validate type, ownership, link count and mode before destructive truncation. */
    if ((flags & O_TRUNC) && ftruncate(fd, 0) != 0) {
        saved = errno;
        close(fd);
        errno = saved;
        return -1;
    }
    return fd;
}

static inline int omega_fs_open_regular(const char *path, int flags, mode_t mode) {
    return omega_fs_open_regular_at(AT_FDCWD, path, flags, mode);
}

static inline int omega_fs_unlink_at(int root_fd, const char *path, int flags) {
    char leaf[OMEGA_FS_NAME_MAX + 1];
    int pfd = omega_fs_parent_open_at(root_fd, path, leaf, sizeof leaf);
    if (pfd < 0) return -1;
    int rc = unlinkat(pfd, leaf, flags);
    int saved = errno;
    close(pfd);
    errno = saved;
    return rc;
}

static inline int omega_fs_rename_at(int root_fd, const char *old_path, const char *new_path) {
    char old_leaf[OMEGA_FS_NAME_MAX + 1], new_leaf[OMEGA_FS_NAME_MAX + 1];
    int old_fd = omega_fs_parent_open_at(root_fd, old_path, old_leaf, sizeof old_leaf);
    if (old_fd < 0) return -1;
    int new_fd = omega_fs_parent_open_at(root_fd, new_path, new_leaf, sizeof new_leaf);
    if (new_fd < 0) {
        close(old_fd);
        return -1;
    }
    int rc = renameat(old_fd, old_leaf, new_fd, new_leaf);
    int saved = errno;
    close(new_fd);
    close(old_fd);
    errno = saved;
    return rc;
}

static inline int omega_fs_link_at(int root_fd, const char *old_path, const char *new_path) {
    char old_leaf[OMEGA_FS_NAME_MAX + 1], new_leaf[OMEGA_FS_NAME_MAX + 1];
    int old_fd = omega_fs_parent_open_at(root_fd, old_path, old_leaf, sizeof old_leaf);
    if (old_fd < 0) return -1;
    int new_fd = omega_fs_parent_open_at(root_fd, new_path, new_leaf, sizeof new_leaf);
    if (new_fd < 0) {
        close(old_fd);
        return -1;
    }
    int rc = linkat(old_fd, old_leaf, new_fd, new_leaf, 0);
    int saved = errno;
    close(new_fd);
    close(old_fd);
    errno = saved;
    return rc;
}

static inline int omega_fs_lstat_at(int root_fd, const char *path, struct stat *st) {
    char leaf[OMEGA_FS_NAME_MAX + 1];
    int pfd = omega_fs_parent_open_at(root_fd, path, leaf, sizeof leaf);
    if (pfd < 0) return -1;
    int rc = fstatat(pfd, leaf, st, AT_SYMLINK_NOFOLLOW);
    int saved = errno;
    close(pfd);
    errno = saved;
    return rc;
}

/* A replaceable destination is either absent or an already validated regular
 * file. Symlinks, hard links, devices and files writable by another uid are
 * unsafe state and must not be silently replaced. */
static inline int omega_fs_replace_ok_at(int root_fd, const char *path) {
    struct stat st;
    if (omega_fs_lstat_at(root_fd, path, &st) != 0) return errno == ENOENT ? 0 : -1;
    if (!S_ISREG(st.st_mode)) {
        errno = EPERM;
        return -1;
    }
    int fd = omega_fs_open_regular_at(root_fd, path, O_RDONLY, 0);
    if (fd < 0) return -1;
    close(fd);
    return 0;
}

static inline int omega_fs_fsync_dir_at(int root_fd, const char *path) {
    int fd = omega_fs_subdir_open(root_fd, path, 0, 0);
    if (fd < 0) return -1;
    int rc = fsync(fd);
    int saved = errno;
    close(fd);
    errno = saved;
    return rc;
}

/* O_EXCL makes a guessed name a refusal, never a target to truncate. PID and
 * a process-local counter keep normal writers from sharing temporary names. */
static inline int omega_fs_temp_name(char *out, size_t cap, const char *stem) {
    static unsigned long long sequence;
    unsigned long long n = __atomic_add_fetch(&sequence, 1, __ATOMIC_RELAXED);
    int wrote = snprintf(out, cap, "%s.%ld.%llu", stem, (long)getpid(), n);
    if (wrote < 0 || (size_t)wrote >= cap) {
        errno = ENAMETOOLONG;
        return -1;
    }
    return 0;
}

#endif /* OMEGA_FS_H */
