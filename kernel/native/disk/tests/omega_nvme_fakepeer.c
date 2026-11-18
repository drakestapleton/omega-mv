/* SPDX-License-Identifier: Apache-2.0
 * Verification fixture for omega_nvme_test.sh: a peer that lives but does not answer the runner.
 * The test puts a copy named qemu-system-aarch64 first in PATH for the runner's QEMU controls, or
 * passes it as the candidate binary. OMEGA_NVME_FAKE selects what it does:
 *   mute      with -qtest unix:PATH,...: open the socket, accept, read and discard, never answer;
 *             as a candidate (no -qtest): read nothing and sleep (asleep, never asks).
 *   nolisten  sleep without opening the socket.
 *   trickle   do not open the socket and stay runnable now and then (a 1 ms spin every 50 ms), so
 *             the runner cannot see it idle and only its 30 s ALARM can end the wait.
 * It exits only when signalled. Not a QEMU, not a driver.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

static double now_s(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
    const char *mode = getenv("OMEGA_NVME_FAKE");
    const char *qtest = NULL;
    for (int i = 1; i + 1 < argc; i++)
        if (!strcmp(argv[i], "-qtest")) qtest = argv[i + 1];
    if (!mode) { fprintf(stderr, "fakepeer: OMEGA_NVME_FAKE unset\n"); return 2; }
    if (!strcmp(mode, "trickle")) {
        struct timespec nap = {0, 50000000};
        for (;;) {
            double t = now_s();
            while (now_s() - t < 0.001) {}
            nanosleep(&nap, NULL);
        }
    }
    if (!strcmp(mode, "nolisten") || (!strcmp(mode, "mute") && !qtest)) {
        for (;;) pause();
    }
    if (strcmp(mode, "mute")) { fprintf(stderr, "fakepeer: unknown mode %s\n", mode); return 2; }
    if (strncmp(qtest, "unix:", 5)) { fprintf(stderr, "fakepeer: -qtest %s is not unix:\n", qtest); return 2; }
    struct sockaddr_un sa = {.sun_family = AF_UNIX};
    size_t n = strcspn(qtest + 5, ",");
    if (n >= sizeof sa.sun_path) { fprintf(stderr, "fakepeer: socket path too long\n"); return 2; }
    memcpy(sa.sun_path, qtest + 5, n);
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s < 0 || bind(s, (struct sockaddr *)&sa, sizeof sa) || listen(s, 1)) { perror("fakepeer socket"); return 2; }
    int c = accept(s, NULL, NULL);
    if (c < 0) { perror("fakepeer accept"); return 2; }
    char buf[512];
    for (;;)
        if (read(c, buf, sizeof buf) <= 0) pause();
}
