/* Independent AArch64 ptrace instrument. No device access. ioctls use fd -1.
 * Observe actual generated arguments; poison only private output pointers after
 * the real EBADF, proving copy-out never discloses compiler-bound addresses. */
#define _GNU_SOURCE
#include <asm/ptrace.h>
#include <elf.h>
#include <errno.h>
#include <linux/kfd_ioctl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>

static void die(const char *s) { perror(s); exit(90); }
static uint64_t peek(pid_t p, uint64_t a) {
    errno=0;
    long v=ptrace(PTRACE_PEEKDATA,p,(void *)(uintptr_t)a,0);
    if (errno) die("peek");
    return (uint64_t)v;
}
static void poke(pid_t p, uint64_t a, uint64_t v) {
    if (ptrace(PTRACE_POKEDATA,p,(void *)(uintptr_t)a,(void *)(uintptr_t)v)) die("poke");
}
int main(int argc, char **argv) {
    if (argc!=2) return 90;
    pid_t p=fork();
    if (p<0) die("fork");
    if (!p) {
        if (ptrace(PTRACE_TRACEME,0,0,0)) _exit(91);
        raise(SIGSTOP);
        execl(argv[1],argv[1],(char *)0);
        _exit(92);
    }
    int status;
    if (waitpid(p,&status,0)!=p || !WIFSTOPPED(status)) die("initial wait");
    if (ptrace(PTRACE_SETOPTIONS,p,0,PTRACE_O_TRACESYSGOOD|PTRACE_O_EXITKILL)) die("options");
    int entering=1, seen=0;
    uint64_t call=0,q=0,h=0,base=0,payload=0,arg0=0,arg1=0;
    unsigned offsets[5],count=0;
    for (;;) {
        if (ptrace(PTRACE_SYSCALL,p,0,0)) die("continue");
        if (waitpid(p,&status,0)!=p) die("wait");
        if (WIFEXITED(status)) {
            if (WEXITSTATUS(status) || seen!=1) {
                fprintf(stderr,"FAIL trace child=%d seen=%d\n",WEXITSTATUS(status),seen);
                return 1;
            }
            fprintf(stderr,"PASS checked binding and private copy-out request=%#llx\n",(unsigned long long)q);
            return 0;
        }
        if (!WIFSTOPPED(status)) return 1;
        if (WSTOPSIG(status)==SIGTRAP) continue;
        if (WSTOPSIG(status)!=(SIGTRAP|0x80)) return 1;
        struct user_pt_regs regs;
        struct iovec io={&regs,sizeof regs};
        if (ptrace(PTRACE_GETREGSET,p,(void *)NT_PRSTATUS,&io)) die("regs");
        if (entering) {
            call=regs.regs[8]; arg0=regs.regs[0]; arg1=regs.regs[1];
            if (call==SYS_write && arg0==1) payload=arg1;
            if (call==SYS_munmap && arg0==base) base+=arg1;
            if (call==SYS_ioctl) {
                if ((int64_t)arg0!=-1) return 1;
                q=arg1; h=regs.regs[2]; count=0;
                uint64_t expected=base;
                switch (q) {
                case AMDKFD_IOC_GET_PROCESS_APERTURES_NEW:
                case AMDKFD_IOC_WAIT_EVENTS:
                    offsets[count++]=0; expected=payload; break;
                case AMDKFD_IOC_MAP_MEMORY_TO_GPU:
                case AMDKFD_IOC_UNMAP_MEMORY_FROM_GPU:
                    offsets[count++]=8; expected=payload; break;
                case AMDKFD_IOC_ALLOC_MEMORY_OF_GPU:
                case AMDKFD_IOC_SET_SCRATCH_BACKING_VA:
                case AMDKFD_IOC_RUNTIME_ENABLE:
                    offsets[count++]=0; break;
                case AMDKFD_IOC_CREATE_QUEUE:
                    offsets[count++]=0; offsets[count++]=8; offsets[count++]=16;
                    offsets[count++]=56; offsets[count++]=72; break;
                case AMDKFD_IOC_GET_VERSION: break;
                default: return 1;
                }
                for (unsigned i=0;i<count;i++) {
                    uint64_t actual=peek(p,h+offsets[i]);
                    if (!expected || actual!=expected) {
                        fprintf(stderr,"FAIL pointer offset=%u actual=%#llx expected=%#llx\n",offsets[i],(unsigned long long)actual,(unsigned long long)expected);
                        return 1;
                    }
                }
                seen++;
            }
        } else {
            if (call==SYS_mmap && (int64_t)regs.regs[0]>=0) base=regs.regs[0];
            if (call==SYS_ioctl) {
                if ((int64_t)regs.regs[0]!=-EBADF) return 1;
                for (unsigned i=0;i<count;i++) poke(p,h+offsets[i],0xdeadbeef);
                if (q==AMDKFD_IOC_GET_VERSION) poke(p,h,0x44332211);
                if (q==AMDKFD_IOC_ALLOC_MEMORY_OF_GPU) poke(p,h+16,0x44332211);
            }
        }
        entering=!entering;
    }
}
