/* Read-only Linux UAPI/layout and syscall verification oracle, not product code.
 * No preload, device access or ioctl emulation beyond one GET_DEVICE_FD return.
 * The child owns a memfd. We substitute that existing fd on GET_DEVICE_FD exit;
 * subsequent IRQ ioctls execute unchanged and must return ENOTTY. */
#define _GNU_SOURCE
#include <asm/ptrace.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/vfio.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/ptrace.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <sys/syscall.h>
#include <signal.h>
#include <unistd.h>
#include <elf.h>

static void die(const char *s) { perror(s); exit(90); }
static uint32_t word(pid_t p, uint64_t address) {
    errno = 0;
    long v = ptrace(PTRACE_PEEKDATA, p, (void *)(uintptr_t)address, 0);
    if (errno) die("PTRACE_PEEKDATA");
    return (uint32_t)v;
}
static void layout(void) {
    printf("irq_info %zu %zu %zu %zu %zu\n", sizeof(struct vfio_irq_info),
           offsetof(struct vfio_irq_info,argsz), offsetof(struct vfio_irq_info,flags),
           offsetof(struct vfio_irq_info,index), offsetof(struct vfio_irq_info,count));
    printf("irq_set %zu %zu %zu %zu %zu %zu %zu\n", sizeof(struct vfio_irq_set),
           offsetof(struct vfio_irq_set,argsz), offsetof(struct vfio_irq_set,flags),
           offsetof(struct vfio_irq_set,index), offsetof(struct vfio_irq_set,start),
           offsetof(struct vfio_irq_set,count), offsetof(struct vfio_irq_set,data));
    printf("requests %lu %lu\n", (unsigned long)VFIO_DEVICE_GET_IRQ_INFO,
           (unsigned long)VFIO_DEVICE_SET_IRQS);
    printf("flags %u %u %u %u\n", VFIO_IRQ_SET_DATA_EVENTFD|VFIO_IRQ_SET_ACTION_TRIGGER,
           VFIO_IRQ_SET_DATA_NONE|VFIO_IRQ_SET_ACTION_TRIGGER,
           VFIO_IRQ_SET_DATA_NONE|VFIO_IRQ_SET_ACTION_MASK,
           VFIO_IRQ_SET_DATA_NONE|VFIO_IRQ_SET_ACTION_UNMASK);
    printf("eventfd %d %ld\n", EFD_CLOEXEC|EFD_NONBLOCK, (long)SYS_eventfd2);
}
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--layout")) { layout(); return 0; }
    if (argc == 2 && !strcmp(argv[1], "--bytes")) {
        struct vfio_irq_info info = {
            .argsz=sizeof info, .flags=VFIO_IRQ_INFO_EVENTFD|VFIO_IRQ_INFO_MASKABLE,
            .index=VFIO_PCI_MSIX_IRQ_INDEX, .count=64
        };
        struct vfio_irq_set set = {
            .argsz=sizeof set+sizeof(int32_t),
            .flags=VFIO_IRQ_SET_DATA_EVENTFD|VFIO_IRQ_SET_ACTION_TRIGGER,
            .index=VFIO_PCI_MSIX_IRQ_INDEX, .start=3, .count=1
        };
        int32_t fd=-1;
        if (fwrite(&info,sizeof info,1,stdout)!=1 ||
            fwrite(&set,sizeof set,1,stdout)!=1 ||
            fwrite(&fd,sizeof fd,1,stdout)!=1) return 1;
        return 0;
    }
    if (argc != 5) return 90;
    int expected = atoi(argv[3]), high = atoi(argv[4]);
    pid_t p = fork();
    if (p < 0) die("fork");
    if (!p) {
        if (high) {
            int fd = 0;
            while (fd < 1100) {
                fd = open("/dev/null", O_RDONLY);
                if (fd < 0) _exit(91);
            }
        }
        if (ptrace(PTRACE_TRACEME, 0, 0, 0)) _exit(92);
        raise(SIGSTOP);
        execl(argv[1], argv[1], argv[2], (char *)0);
        _exit(93);
    }
    int status;
    if (waitpid(p, &status, 0) != p || !WIFSTOPPED(status)) die("initial wait");
    if (ptrace(PTRACE_SETOPTIONS, p, 0, PTRACE_O_TRACESYSGOOD|PTRACE_O_EXITKILL)) die("options");
    int entering = 1, fakefd = -1, eventfd = -1, irq = 0, injected = 0;
    uint64_t call = 0, request = 0, fd = 0;
    for (;;) {
        if (ptrace(PTRACE_SYSCALL, p, 0, 0)) die("continue");
        if (waitpid(p, &status, 0) != p) die("waitpid");
        if (WIFEXITED(status)) {
            int rc = WEXITSTATUS(status);
            int wanted_irq = !strcmp(argv[2],"0") ? 7 : (!strcmp(argv[2],"@") ? 1 : 0);
            if (rc != expected || injected != 1 || irq != wanted_irq) {
                fprintf(stderr,"FAIL fixture exit=%d expected=%d injected=%d irq=%d\n",rc,expected,injected,irq);
                return 1;
            }
            printf("PASS ptrace fixture mode=%s exit=%d IRQ_ENOTTY=%d highfd=%d\n",argv[2],rc,irq,high);
            return 0;
        }
        if (!WIFSTOPPED(status) || WSTOPSIG(status) != (SIGTRAP|0x80)) {
            if (WIFSTOPPED(status) && WSTOPSIG(status) == SIGTRAP) continue;
            fprintf(stderr,"FAIL unexpected child status=%d\n",status); return 1;
        }
        struct user_pt_regs regs;
        struct iovec io = { &regs, sizeof regs };
        if (ptrace(PTRACE_GETREGSET,p,(void *)NT_PRSTATUS,&io)) die("getregset");
        if (entering) {
            call=regs.regs[8]; request=regs.regs[1]; fd=regs.regs[0];
            if (call == SYS_eventfd2 &&
                regs.regs[1] != (EFD_CLOEXEC|EFD_NONBLOCK)) return 1;
            if (call == SYS_ioctl && request == VFIO_GROUP_GET_DEVICE_FD) {
                fakefd=(int)fd;
                if (high && fakefd < 1024) return 1;
            }
            if (call == SYS_ioctl && (request == VFIO_DEVICE_GET_IRQ_INFO || request == VFIO_DEVICE_SET_IRQS)) {
                if ((int)fd != fakefd) return 1;
                uint64_t b=regs.regs[2];
                uint32_t sz=word(p,b);
                if (request == VFIO_DEVICE_GET_IRQ_INFO) {
                    if (sz != sizeof(struct vfio_irq_info)) return 1;
                } else {
                    uint32_t flags=word(p,b+offsetof(struct vfio_irq_set,flags));
                    uint32_t count=word(p,b+offsetof(struct vfio_irq_set,count));
                    if (count > 64) return 1;
                    if (flags == (VFIO_IRQ_SET_DATA_EVENTFD|VFIO_IRQ_SET_ACTION_TRIGGER)) {
                        if (!count || sz != sizeof(struct vfio_irq_set)+sizeof(int32_t)*count) return 1;
                        for (uint32_t i=0; i<count; i++) {
                            int32_t e=(int32_t)word(p,b+offsetof(struct vfio_irq_set,data)+sizeof(int32_t)*i);
                            if (e != eventfd && e != -1) return 1;
                        }
                    } else if (sz != sizeof(struct vfio_irq_set)) return 1;
                }
            }
        } else {
            if (call == SYS_eventfd2 && (int64_t)regs.regs[0] >= 0) eventfd=(int)regs.regs[0];
            if (call == SYS_ioctl && request == VFIO_GROUP_GET_DEVICE_FD) {
                if ((int64_t)regs.regs[0] != -ENOTTY) return 1;
                regs.regs[0]=(uint64_t)fakefd;
                if (ptrace(PTRACE_SETREGSET,p,(void *)NT_PRSTATUS,&io)) die("setregset");
                injected++;
            }
            if (call == SYS_ioctl && (request == VFIO_DEVICE_GET_IRQ_INFO || request == VFIO_DEVICE_SET_IRQS)) {
                if ((int64_t)regs.regs[0] != -ENOTTY) return 1;
                irq++;
            }
        }
        entering=!entering;
    }
}
