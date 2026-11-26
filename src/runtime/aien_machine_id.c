/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Drake Stapleton (AIEN / aien-dev)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * aien_machine_id.c -- persistence and the local index table for the
 * canonical machine identity. The codec is in aien_machine_id.h.
 */
#include "aien_machine_id.h"
#include "omega_fs.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

static int write_all(int fd, const uint8_t *p, size_t n) {
    while (n) {
        ssize_t w = write(fd, p, n);
        if (w < 0) { if (errno == EINTR) continue; return -1; }
        p += (size_t)w; n -= (size_t)w;
    }
    return 0;
}

int aien_mid_store_at(int dir_fd, const char *name, const AienMachineId *m) {
    if (dir_fd < 0 || !name || !m || strchr(name, '/')) return AIEN_MID_E_ARG;
    uint8_t rec[AIEN_MID_RECORD_BYTES];
    int rc = aien_mid_encode(m, rec);
    if (rc != AIEN_MID_OK) return rc;
    if (omega_fs_replace_ok_at(dir_fd, name) != 0) return AIEN_MID_E_IO;

    char stem[OMEGA_FS_NAME_MAX + 1], tmp[OMEGA_FS_NAME_MAX + 1];
    if ((size_t)snprintf(stem, sizeof stem, "%s.tmp", name) >= sizeof stem ||
        omega_fs_temp_name(tmp, sizeof tmp, stem) != 0)
        return AIEN_MID_E_ARG;
    int fd = omega_fs_open_regular_at(dir_fd, tmp, O_WRONLY | O_CREAT | O_EXCL, 0644);
    if (fd < 0) return AIEN_MID_E_IO;
    if (write_all(fd, rec, sizeof rec) != 0 || fsync(fd) != 0) {
        close(fd); omega_fs_unlink_at(dir_fd, tmp, 0); return AIEN_MID_E_IO;
    }
    if (close(fd) != 0 || omega_fs_rename_at(dir_fd, tmp, name) != 0 || fsync(dir_fd) != 0) {
        omega_fs_unlink_at(dir_fd, tmp, 0);
        return AIEN_MID_E_IO;
    }
    return AIEN_MID_OK;
}

int aien_mid_load_at(int dir_fd, const char *name, AienMachineId *out) {
    if (dir_fd < 0 || !name || !out || strchr(name, '/')) return AIEN_MID_E_ARG;
    int fd = omega_fs_open_regular_at(dir_fd, name, O_RDONLY, 0);
    if (fd < 0) return AIEN_MID_E_IO;
    uint8_t buf[AIEN_MID_RECORD_BYTES + 1];
    size_t got = 0;
    for (;;) {   /* read one byte past a record so a longer file is caught */
        ssize_t r = read(fd, buf + got, sizeof buf - got);
        if (r < 0) { if (errno == EINTR) continue; close(fd); return AIEN_MID_E_IO; }
        if (r == 0) break;
        got += (size_t)r;
        if (got == sizeof buf) break;
    }
    close(fd);
    return aien_mid_decode(buf, got, out);
}

int aien_mid_store(const char *path, const AienMachineId *m) {
    if (!path || !m) return AIEN_MID_E_ARG;
    char checked[OMEGA_FS_PATH_MAX];
    if (omega_path_copy(checked, sizeof checked, path) != 0) return AIEN_MID_E_ARG;
    char name[OMEGA_FS_NAME_MAX + 1];
    int dir_fd = omega_fs_parent_open_at(AT_FDCWD, checked, name, sizeof name);
    if (dir_fd < 0) return AIEN_MID_E_IO;
    int rc = aien_mid_store_at(dir_fd, name, m);
    close(dir_fd);
    return rc;
}

int aien_mid_load(const char *path, AienMachineId *out) {
    if (!path || !out) return AIEN_MID_E_ARG;
    char checked[OMEGA_FS_PATH_MAX];
    if (omega_path_copy(checked, sizeof checked, path) != 0) return AIEN_MID_E_ARG;
    char name[OMEGA_FS_NAME_MAX + 1];
    int dir_fd = omega_fs_parent_open_at(AT_FDCWD, checked, name, sizeof name);
    if (dir_fd < 0) return AIEN_MID_E_IO;
    int rc = aien_mid_load_at(dir_fd, name, out);
    close(dir_fd);
    return rc;
}

void aien_mid_index_init(AienMachineIndex *t, AienMachineId *slots, uint32_t capacity) {
    t->capacity = slots ? capacity : 0;
    t->count = 0;
    t->slots = slots;
}

uint32_t aien_mid_index_find(const AienMachineIndex *t, const AienMachineId *m) {
    if (!t || !m) return 0;
    for (uint32_t i = 0; i < t->count; i++)
        if (aien_mid_equal(&t->slots[i], m)) return i + 1;
    return 0;
}

uint32_t aien_mid_index_bind(AienMachineIndex *t, const AienMachineId *m) {
    if (!t || !m || aien_mid_is_zero_(m->id) || !aien_mid_root_valid_(m->root)) return 0;
    uint32_t k = aien_mid_index_find(t, m);
    if (k) return k;
    if (t->count >= t->capacity) return 0;
    t->slots[t->count] = *m;
    return ++t->count;
}

int aien_mid_index_get(const AienMachineIndex *t, uint32_t index, AienMachineId *out) {
    if (!t || !out || index == 0 || index > t->count) return AIEN_MID_E_ARG;
    *out = t->slots[index - 1];
    return AIEN_MID_OK;
}
