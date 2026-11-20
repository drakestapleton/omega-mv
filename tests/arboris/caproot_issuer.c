/* SPDX-License-Identifier: AGPL-3.0-only
 * Exercise the OM admission decision with the resident runtime's sealed table. */
#include "runtime/rx_caproot.h"
#include <stddef.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#define GPU_RESOURCE UINT64_C(0x4152425247423130)
_Static_assert(sizeof(RxCapTable) == 22560 && sizeof(RxCapEntry) == 88, "caproot ABI");
_Static_assert(offsetof(RxCapTable, entries) == 32 && offsetof(RxCapEntry, parent_generation) == 64, "caproot ABI");

static int check(const char *program, const RxCapRoot *root, uint32_t subject,
                 RxCapRef ref, uint64_t epoch, uint64_t planned_gen, int allow) {
    int input[2];
    if (pipe(input) < 0) return 1;
    pid_t pid = fork();
    if (pid == 0) {
        if (dup2(input[0], STDIN_FILENO) < 0 || dup2(root->ro_fd, 3) < 0 ||
            fcntl(3, F_SETFD, 0) < 0) _exit(126);
        close(input[1]);
        execl(program, program, (char *)NULL);
        _exit(127);
    }
    close(input[0]);
    uint64_t request[] = {subject, ref.cap_id, ref.generation, epoch, planned_gen, (uint64_t)allow};
    int bad = pid < 0 || write(input[1], request, sizeof request) != sizeof request;
    close(input[1]);
    int status;
    if (pid <= 0 || waitpid(pid, &status, 0) != pid || !WIFEXITED(status)) return 1;
    if (bad || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "admission test failed, expected %d, runner exit %d\n", allow, WEXITSTATUS(status));
        return 1;
    }
    return 0;
}

static int exercise(const char *program, RxCapRoot *root, RxCapAdmin *admin) {
    RxCapMint mint = {.subject = 42, .resource = GPU_RESOURCE, .rights = RX_RIGHT_EFFECT | RX_RIGHT_DELEGATE,
                      .lease_ticks = 2, .parent = {UINT32_MAX, 0}, .authority = admin->office};
    RxCapRef parent, child, wrong;
    if (rx_capadmin_mint(admin, &mint, &parent) != RX_CAP_OK) return 1;
    mint.authority = mint.parent = parent;
    mint.rights = RX_RIGHT_EFFECT;
    mint.lease_ticks = 1;
    if (rx_capadmin_mint(admin, &mint, &child) != RX_CAP_OK) return 1;
    if (check(program, root, 42, child, 1, child.generation, 1) ||
        check(program, root, 43, child, 1, child.generation, 0) ||
        check(program, root, 42, child, 2, child.generation, 0) ||
        check(program, root, 42, child, 1, child.generation + 1, 0)) return 1;
    mint.authority = admin->office;
    mint.parent = (RxCapRef){UINT32_MAX, 0};
    mint.resource++;
    if (rx_capadmin_mint(admin, &mint, &wrong) != RX_CAP_OK ||
        check(program, root, 42, wrong, 1, wrong.generation, 0)) return 1;
    mint.resource = GPU_RESOURCE;
    mint.rights = RX_RIGHT_READ;
    if (rx_capadmin_mint(admin, &mint, &wrong) != RX_CAP_OK ||
        check(program, root, 42, wrong, 1, wrong.generation, 0)) return 1;
    if (rx_capadmin_advance_clock(admin, admin->office, 1) != RX_CAP_OK ||
        check(program, root, 42, child, 1, child.generation, 0) ||
        check(program, root, 42, parent, 1, parent.generation, 1)) return 1;
    if (rx_capadmin_revoke(admin, admin->office, parent) != RX_CAP_OK ||
        check(program, root, 42, parent, 1, parent.generation, 0)) return 1;
    return 0;
}

int main(int argc, char **argv) {
    RxCapRoot root;
    RxCapAdmin admin;
    int device = argc == 3 && (strcmp(argv[2], "--sparse-silicon") == 0 ||
                               strcmp(argv[2], "--arboris-silicon") == 0);
    if ((!device && argc != 2) || rx_caproot_start(&root, &admin) != RX_CAP_OK) return 1;
    int result;
    if (device) {
        RxCapMint mint = {.subject = 42, .resource = GPU_RESOURCE, .rights = RX_RIGHT_EFFECT,
                          .parent = {UINT32_MAX, 0}, .authority = admin.office};
        RxCapRef ref;
        result = rx_capadmin_mint(&admin, &mint, &ref) != RX_CAP_OK ||
                 check(argv[1], &root, 42, ref, 1, ref.generation, 1);
    } else {
        result = exercise(argv[1], &root, &admin);
    }
    rx_caproot_stop(&root, &admin);
    if (result == 0 && !device) puts("PASS sealed capability root, delegated effect, scope, epoch, generation, expiry and revocation");
    return result;
}
