/* Independent AArch64 syscall-boundary instrument; no AMD device is opened.
 * A real memfd supplies mmap backing. Only stat metadata is synthetic. */
#define _GNU_SOURCE
#include <asm/ptrace.h>
#include <elf.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ptrace.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>

static void die(const char *s) { perror(s); exit(90); }
static void poke(pid_t p, uint64_t a, const void *src, size_t n) {
    const unsigned char *s=src;
    for (size_t i=0;i<n;i+=sizeof(long)) {
        long v=0;
        memcpy(&v,s+i,n-i<sizeof v?n-i:sizeof v);
        if (ptrace(PTRACE_POKEDATA,p,(void *)(uintptr_t)(a+i),(void *)v)) die("poke");
    }
}
int main(int argc, char **argv) {
    if (argc!=4) return 90;
    unsigned mode=(unsigned)strtoul(argv[2],0,10);
    uint64_t bytes=strtoull(argv[3],0,10);
    int success=mode==0 || mode==2;
    pid_t p=fork();
    if (p<0) die("fork");
    if (!p) {
        if (ptrace(PTRACE_TRACEME,0,0,0)) _exit(91);
        raise(SIGSTOP);
        execl(argv[1],argv[1],(char *)0);
        _exit(92);
    }
    int status;
    if (waitpid(p,&status,0)!=p || !WIFSTOPPED(status)) die("wait");
    if (ptrace(PTRACE_SETOPTIONS,p,0,PTRACE_O_TRACESYSGOOD|PTRACE_O_EXITKILL)) die("options");
    int entering=1, maps=0, stats=0;
    uint64_t call=0,buf=0;
    for (;;) {
        if (ptrace(PTRACE_SYSCALL,p,0,0)) die("continue");
        if (waitpid(p,&status,0)!=p) die("wait");
        if (WIFEXITED(status)) {
            int expected=success?0:103;
            if (WEXITSTATUS(status)!=expected || maps!=success || stats<1) return 1;
            fprintf(stderr,"PASS synthetic fd mode=%u maps=%d child=%d span=%llu\n",mode,maps,expected,(unsigned long long)bytes);
            return 0;
        }
        if (!WIFSTOPPED(status)) return 1;
        if (WSTOPSIG(status)==SIGTRAP) continue;
        if (WSTOPSIG(status)!=(SIGTRAP|0x80)) return 1;
        struct user_pt_regs regs;
        struct iovec io={&regs,sizeof regs};
        if (ptrace(PTRACE_GETREGSET,p,(void *)NT_PRSTATUS,&io)) die("regs");
        if (entering) {
            call=regs.regs[8];
            if (call==SYS_fstat) buf=regs.regs[1];
            if (call==SYS_newfstatat) buf=regs.regs[2];
            if (call==SYS_mmap) {
                if (regs.regs[1]!=bytes || regs.regs[2]!=3 || regs.regs[3]!=1) return 1;
                maps++;
            }
        } else if (call==SYS_fstat || call==SYS_newfstatat) {
            struct stat st={0};
            st.st_mode=S_IFCHR|0600;
            st.st_rdev=makedev(226,128);
            if (mode==1) st.st_rdev=makedev(226,127);
            if (mode>=2) st.st_rdev=makedev(234,0);
            if (call==SYS_newfstatat) st.st_rdev=makedev(234,0);
            if (call==SYS_newfstatat && mode==3) st.st_rdev=makedev(234,1);
            if (call==SYS_newfstatat && mode==4) st.st_mode=S_IFREG|0600;
            if (call==SYS_fstat && mode==5) st.st_mode=S_IFREG|0600;
            poke(p,buf,&st,sizeof st);
            regs.regs[0]=0;
            if (mode==6) regs.regs[0]=(uint64_t)-EBADF;
            if (ptrace(PTRACE_SETREGSET,p,(void *)NT_PRSTATUS,&io)) die("setregs");
            stats++;
        }
        entering=!entering;
    }
}
