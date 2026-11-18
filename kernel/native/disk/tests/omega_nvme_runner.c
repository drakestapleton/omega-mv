/* SPDX-License-Identifier: Apache-2.0
 * Verification-only byte transport and existing C model/oracle, not a driver.
 * Never accepts a block device. QEMU runs stopped with a disposable regular image.
 */
#define _POSIX_C_SOURCE 200809L
#define main original_reference_tests_main
#include "nvme_test.c"
#undef main
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <time.h>
#include <dirent.h>

static int qfd = -1, outfd, infd, errors, published, reported, retained, alarms;
static pid_t qp = -1, child = -1;
static char tempdir[128], image[180], socketpath[180], qlog[180];
static uint8_t expected[8192];
static size_t wanted;
static const char *scenario;
static int result_code = -1;
/* The engine's wait budget as omega_nvme.om states it: ready() polls CSTS `for i ulong 256` with
 * `transport_wait 1000` after each miss; submit() polls the completion slot `for i ulong 256` with
 * `transport_wait 100`. These are the verifier's copy of that specification. A timeout case must
 * wait exactly ENGINE_POLLS times in its longest loop, with a delay total of ENGINE_POLLS times the
 * loop's wait length, and a wait of another length fails the case, so an engine whose budget
 * differs fails here whatever the script says [ctl:OMEGA-KERNEL-OMEGA-NVME/mutant-budget255]. */
#define ENGINE_POLLS 256u
#define ENGINE_READY_WAIT_US 1000u
#define ENGINE_CMD_WAIT_US 100u
/* Engine waits (RPC op 9, transport_wait): the run of waits since the engine last wrote anything is
 * one wait loop. QEMU mode allows QEMU_MAX_WAITS of the engine's 256 per loop: each wait lets QEMU
 * run until idle, so a completion needs one; more means the engine is living on its budget, and the
 * case FAILS (printed as waits= and maxwait=) [ctl:OMEGA-KERNEL-OMEGA-NVME/mutant-qemu-max-waits]. */
#define QEMU_MAX_WAITS 8u
static unsigned waits, run_waits, max_waits, min_waits, bad_waits;
static uint64_t run_delay, max_run_delay;
/* Slow case (C model): every SQ doorbell takes effect only after SLOW_CMD_US of engine waits, and
 * CSTS.RDY reads 0 for SLOW_READY_US after the enable: half of each loop's budget (SLOW_HOLD_WAITS
 * waits of the loop's length). Each wait loop of the case must take exactly SLOW_HOLD_WAITS waits;
 * a budget cut to 1 (or no wait at all) times out, result 12. */
#define SLOW_HOLD_WAITS (ENGINE_POLLS / 2u)
#define SLOW_CMD_US (SLOW_HOLD_WAITS * ENGINE_CMD_WAIT_US)
#define SLOW_READY_US (SLOW_HOLD_WAITS * ENGINE_READY_WAIT_US)
static uint64_t hold_us, ready_hold_us;
static int held;
static uint32_t held_off, held_val;
static void die(const char *s) { perror(s); exit(2); }
static void check(int b, const char *s) { if (!b) { fprintf(stderr,"FAIL %s: %s\n",scenario,s); errors++; } }
static double now_s(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return (double)t.tv_sec + t.tv_nsec / 1e9; }
/* A peer (QEMU or the candidate) that has not answered for 30 s prints an ALARM line and ends the
 * run, exit 2. omega_nvme_test.sh counts ALARM lines in the logs of its runs and fails on one
 * [ctl:OMEGA-KERNEL-OMEGA-NVME/alarm-printed-counted]. */
#define ALARM_S 30.0
static void alarm_line(const char *what, double s)
{
    alarms++;
    fprintf(stderr,"ALARM %s: %.0f s waiting on %s (the case FAILS)\n",scenario,s,what);
}
static void alarm_end(const char *what, double s)
{
    alarm_line(what,s);
    fprintf(stderr,"FAIL %s: PEER_SILENT no answer from %s for %.0f s, run ended\n",scenario,what,s);
    exit(2);
}
/* State letter of /proc/P/stat (the field after the last ')'), or 0 when it cannot be read. */
static char proc_state(pid_t p)
{
    char path[64], buf[512];
    snprintf(path,sizeof path,"/proc/%ld/stat",(long)p);
    FILE *f = fopen(path,"r");
    if (!f) return 0;
    size_t k = fread(buf,1,sizeof buf-1,f); fclose(f); buf[k] = 0;
    char *s = strrchr(buf,')');
    return s && s[1] == ' ' ? s[2] : 0;
}
/* A QEMU that exited (reaped here) or is a zombie (state Z or X) ends the run at once: QEMU_DEAD,
 * exit 2 [ctl:OMEGA-KERNEL-OMEGA-NVME/qemu-killed]. A stopped QEMU (state T or t) ends it too:
 * QEMU_STOPPED, exit 2 [ctl:OMEGA-KERNEL-OMEGA-NVME/qemu-stopped]. */
static void qemu_check(void)
{
    if (qp <= 0) return;
    int st = 0;
    pid_t w = waitpid(qp,&st,WNOHANG);
    if (w == qp) {
        qp = -1;
        fprintf(stderr,"FAIL %s: QEMU_DEAD QEMU exited during the run (%s %d)\n",scenario,
                WIFSIGNALED(st) ? "signal" : "status", WIFSIGNALED(st) ? WTERMSIG(st) : WEXITSTATUS(st));
        exit(2);
    }
    char c = proc_state(qp);
    if (c == 'Z' || c == 'X') {
        fprintf(stderr,"FAIL %s: QEMU_DEAD QEMU is a zombie (state %c)\n",scenario,c);
        kill(qp,SIGKILL); waitpid(qp,NULL,0); qp = -1;
        exit(2);
    }
    if (c == 'T' || c == 't') {
        fprintf(stderr,"FAIL %s: QEMU_STOPPED QEMU is stopped (state %c)\n",scenario,c);
        exit(2);
    }
}
/* The candidate stopped (state T or t) ends the run: CANDIDATE_STOPPED, exit 2. Its exit shows as
 * EOF on its stream and is judged by its exit code. */
static void candidate_check(void)
{
    if (child <= 0) return;
    char c = proc_state(child);
    if (c == 'T' || c == 't') {
        fprintf(stderr,"FAIL %s: CANDIDATE_STOPPED the candidate is stopped (state %c)\n",scenario,c);
        exit(2);
    }
}
static void peer_check(pid_t p) { if (p == qp) qemu_check(); else candidate_check(); }
/* Idle test for a peer process (QEMU or the candidate). QEMU's NVMe model finishes a read on its own
 * threads (the block layer's thread pool, then bottom halves on the main loop), so whether a
 * completion has landed at a given register read depends on host scheduling. The engine reads
 * whatever QEMU shows (QEMU stays asynchronous); when it waits (op 9, transport_wait), the runner
 * waits until QEMU is idle: each thread asleep (S) in two reads of /proc with no thread run in
 * between. So one engine wait covers a completion at the loads tried, and the per-loop wait count
 * (QEMU_MAX_WAITS) shows whether the 256-wait budget is being used. The budget itself is checked by
 * the C-model slow and timeout cases and their mutants (omega_nvme_test.sh).
 * A thread that exits between the directory read and the read of its files makes the scan start
 * again (after checking that the process lives); NOT_RUN (exit 3) only when /proc has no task list
 * or a live thread has no schedstat (a kernel without schedstats). */
static int snapshot(pid_t p, unsigned long long *ran, unsigned *threads)
{
    char path[320], buf[512];  /* d_name is at most 255 bytes */
    double since = now_s();
    for (;;) {
        peer_check(p);
        char c = proc_state(p);
        if (!c || c == 'Z' || c == 'X') { peer_check(p); return 0; }  /* the candidate exited: EOF follows */
        snprintf(path,sizeof path,"/proc/%ld/task",(long)p);
        DIR *d = opendir(path);
        if (!d) {
            peer_check(p);
            fprintf(stderr,"NOT_RUN %s: cannot read %s to tell when a peer is idle\n",scenario,path);
            exit(3);
        }
        int asleep = 1, vanished = 0; struct dirent *e;
        *ran = 0; *threads = 0;
        while (!vanished && (e = readdir(d))) {
            if (e->d_name[0] < '0' || e->d_name[0] > '9') continue;
            unsigned long long ns = 0, slices = 0;
            snprintf(path,sizeof path,"/proc/%ld/task/%s/stat",(long)p,e->d_name);
            FILE *f = fopen(path,"r");
            if (!f) { vanished = 1; break; }
            size_t k = fread(buf,1,sizeof buf-1,f); fclose(f); buf[k] = 0;
            char *s = strrchr(buf,')');
            if (!s || s[1] != ' ' || s[2] != 'S') asleep = 0;
            snprintf(path,sizeof path,"/proc/%ld/task/%s/schedstat",(long)p,e->d_name);
            f = fopen(path,"r");
            if (!f) {
                snprintf(path,sizeof path,"/proc/%ld/task/%s",(long)p,e->d_name);
                if (access(path,F_OK) != 0) { vanished = 1; break; }
                snprintf(path,sizeof path,"/proc/%ld/task/%s/schedstat",(long)p,e->d_name);
                if (access(path,F_OK) == 0) { asleep = 0; continue; }
                fprintf(stderr,"NOT_RUN %s: no %s (thread run times) to tell when a peer is idle\n",scenario,path);
                closedir(d); exit(3);
            }
            if (fscanf(f,"%llu %*u %llu",&ns,&slices) != 2) asleep = 0;
            fclose(f);
            *ran += ns + slices; (*threads)++;
        }
        closedir(d);
        if (!vanished) return asleep && *threads > 0;
        double w = now_s() - since;
        if (w >= ALARM_S) alarm_end("a stable thread list in /proc", w);
    }
}
/* A live peer that does not answer while it is idle (snapshot asleep twice, a poll timeout apart,
 * with no run time between) will not answer: QEMU_MUTE or CANDIDATE_MUTE, exit 2
 * [ctl:OMEGA-KERNEL-OMEGA-NVME/qemu-mute] [ctl:OMEGA-KERNEL-OMEGA-NVME/candidate-mute]. */
struct idle { int have; unsigned long long ran; unsigned threads; };
static void mute_check(pid_t p, struct idle *last, const char *doing)
{
    unsigned long long ran; unsigned threads;
    if (p <= 0) return;
    int asleep = snapshot(p,&ran,&threads);
    if (asleep && last->have && last->ran == ran && last->threads == threads) {
        fprintf(stderr,"FAIL %s: %s %s is idle (its %u threads asleep, none ran between two reads 1 s apart) %s\n",
                scenario,p == qp ? "QEMU_MUTE" : "CANDIDATE_MUTE",p == qp ? "QEMU" : "the candidate",threads,doing);
        exit(2);
    }
    last->have = asleep; last->ran = ran; last->threads = threads;
}
/* Waits have no wall-clock deadline while the peer works. A peer that exits closes its end (EOF or
 * EPIPE); each second without progress the peer is checked: dead, stopped or idle ends the run
 * (exit 2, above). A peer that is runnable but has not answered for 30 s gets an ALARM line and
 * the run ends (alarm_end). */
static int exact(int fd, void *p, size_t n, int writing)
{
    size_t done = 0;
    double since = now_s();
    struct idle last = {0,0,0};
    while (done < n) {
        struct pollfd f = {fd, writing ? POLLOUT : POLLIN, 0};
        int k = poll(&f,1,1000);
        if (k < 0 && errno == EINTR) continue;
        if (k < 0) return -1;
        if (k == 0) {
            pid_t peer = fd == qfd ? qp : child;
            peer_check(peer);
            mute_check(peer,&last,writing ? "and does not read the runner's request" : "and has not answered");
            double w = now_s() - since;
            if (w >= ALARM_S) alarm_end(fd == qfd ? "the QEMU qtest socket" : "the candidate", w);
            continue;
        }
        ssize_t r = writing ? write(fd,(char *)p+done,n-done) : read(fd,(char *)p+done,n-done);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) { if (fd == qfd) qemu_check(); return -1; }
        done += (size_t)r;
        since = now_s(); last.have = 0;
    }
    return 0;
}
static void qemu_settle(void)
{
    struct timespec nap = {0,50000};
    unsigned long long a, b; unsigned na, nb;
    double since = now_s();
    for (;;) {
        if (snapshot(qp,&a,&na) && snapshot(qp,&b,&nb) && a == b && na == nb) return;
        double w = now_s() - since;
        if (w >= ALARM_S) alarm_end("QEMU to go idle", w);
        nanosleep(&nap,NULL);
    }
}
/* Reap a child at the end of the run. A stopped child (state T or t) gets SIGKILL at once and the
 * run fails (STOPPED, exit 2). Otherwise an ALARM after 30 s, then SIGKILL (a disposable QEMU or
 * candidate that ignores SIGTERM). Returns 1 when the run must fail. */
static int reap(pid_t p, int sig, const char *who)
{
    struct timespec nap = {0,10000000};
    double since = now_s(), next = ALARM_S;
    int failed = 0;
    char c = proc_state(p);
    if (c == 'T' || c == 't') {
        fprintf(stderr,"FAIL %s: STOPPED %s was stopped (state %c) at the end of the run\n",scenario,who,c);
        failed = 1; sig = SIGKILL;
    }
    kill(p,sig);
    while (waitpid(p,NULL,WNOHANG) == 0) {
        double w = now_s() - since;
        if (w >= next) { alarm_line(who, w); failed = 1; next += ALARM_S; kill(p,SIGKILL); }
        nanosleep(&nap,NULL);
    }
    return failed;
}
static void cleanup(void)
{
    int alarmed = 0;
    if (child > 0) { alarmed |= reap(child,SIGKILL,"the candidate"); child = -1; }
    if (qp > 0) { alarmed |= reap(qp,SIGTERM,"QEMU"); qp = -1; }
    if (qfd >= 0) close(qfd);
    if (*image) unlink(image);
    if (*socketpath) unlink(socketpath);
    /* Keep QEMU stderr as an artifact when requested by the caller. */
    if (*qlog) unlink(qlog);
    if (*tempdir) rmdir(tempdir);
    if (alarmed) _exit(2);
}
static uint64_t qt(const char *fmt,...)
{
    char line[512], response[256];
    va_list a; va_start(a,fmt); vsnprintf(line,sizeof line,fmt,a); va_end(a);
    size_t n = strlen(line); line[n++]='\n';
    if (exact(qfd,line,n,1)) die("qtest send");
    n=0;
    do { if (n+1 >= sizeof response || exact(qfd,response+n,1,0)) die("qtest response"); } while (response[n++]!='\n');
    response[n]=0;
    if (strncmp(response,"OK",2)) { fprintf(stderr,"qtest: %s",response); exit(2); }
    return response[2]==' ' ? strtoull(response+3,NULL,0) : 0;
}
static void start_qemu(void)
{
    strcpy(tempdir,"/tmp/omega-nvme-XXXXXX");
    if (!mkdtemp(tempdir)) die("mkdtemp");
    snprintf(image,sizeof image,"%s/namespace.raw",tempdir);
    snprintf(socketpath,sizeof socketpath,"%s/qtest",tempdir);
    snprintf(qlog,sizeof qlog,"%s/qemu.log",tempdir);
    int fd=open(image,O_CREAT|O_EXCL|O_RDWR,0600); if (fd<0) die("image");
    struct stat st; if (fstat(fd,&st) || !S_ISREG(st.st_mode)) die("regular image");
    uint8_t block[4096];
    for (size_t pos=0;pos<4096u*512u;pos+=sizeof block) {
        for (size_t j=0;j<sizeof block;j++) block[j]=(uint8_t)(7u*37u+(pos+j)*13u+((pos+j)>>8));
        if (write(fd,block,sizeof block)!=(ssize_t)sizeof block) die("image fixture");
    }
    close(fd);
    char drive[256], qtest[256];
    snprintf(drive,sizeof drive,"if=none,id=ns,file=%s,format=raw",image);
    snprintf(qtest,sizeof qtest,"unix:%s,server=on,wait=off",socketpath);
    qp=fork(); if (qp<0) die("fork qemu");
    if (!qp) {
        int log=open(qlog,O_CREAT|O_WRONLY,0600); dup2(log,2); close(log);
        execlp("qemu-system-aarch64","qemu-system-aarch64","-machine","virt","-accel","tcg","-S","-m","64M","-nodefaults","-display","none","-monitor","none","-serial","none","-qtest",qtest,"-drive",drive,"-device","nvme,drive=ns,serial=OMEGA-FIXTURE-000001,addr=1.0",NULL);
        _exit(127);
    }
    struct sockaddr_un sa={.sun_family=AF_UNIX}; strcpy(sa.sun_path,socketpath);
    struct timespec nap={0,10000000};
    /* No deadline while QEMU works toward its socket. An exited or stopped QEMU ends the wait at
     * once (qemu_check); one that sits idle for a second without opening the socket ends it with
     * QEMU_NOT_LISTENING [ctl:OMEGA-KERNEL-OMEGA-NVME/qemu-not-listening]; one still runnable after
     * 30 s gets an ALARM line and ends it [ctl:OMEGA-KERNEL-OMEGA-NVME/alarm-printed-counted]. */
    double since = now_s(), snap = since;
    struct idle last = {0,0,0};
    for (;;) {
        qfd=socket(AF_UNIX,SOCK_STREAM,0);
        if (qfd<0) die("socket");
        if (connect(qfd,(struct sockaddr *)&sa,sizeof sa)==0) break;
        close(qfd); qfd=-1;
        int st=0;
        if (waitpid(qp,&st,WNOHANG)==qp) {
            qp=-1;
            fprintf(stderr,"FAIL %s: QEMU_DEAD QEMU exited (status %d) before its qtest socket opened\n",scenario,st);
            exit(2);
        }
        double t = now_s();
        if (t - snap >= 1.0) {
            unsigned long long ran; unsigned threads;
            int asleep = snapshot(qp,&ran,&threads);
            if (asleep && last.have && last.ran == ran && last.threads == threads) {
                fprintf(stderr,"FAIL %s: QEMU_NOT_LISTENING QEMU is idle (its %u threads asleep, none ran between two reads 1 s apart) and its qtest socket is not open\n",scenario,threads);
                exit(2);
            }
            last.have = asleep; last.ran = ran; last.threads = threads; snap = t;
        }
        if (t - since >= ALARM_S) alarm_end("QEMU to open its qtest socket", t - since);
        nanosleep(&nap,NULL);
    }
    /* virt ECAM, bus0/dev1/function0. PCI binding is verifier setup, not .om NVMe logic. */
    uint64_t ecam=0x4010008000ull;
    check((qt("readl 0x%llx",(unsigned long long)ecam)&0xffff)==0x1b36,"QEMU NVMe vendor");
    qt("writel 0x%llx 0x10000004",(unsigned long long)(ecam+0x10));
    qt("writel 0x%llx 0",(unsigned long long)(ecam+0x14));
    qt("writew 0x%llx 6",(unsigned long long)(ecam+4));
}
static int iscase(const char *s) { return !strcmp(scenario,s); }
static void inject_io(void)
{
    if (iscase("cid")) M.bad_cid=1;
    if (iscase("sqid")) M.bad_sqid=1;
    if (iscase("timeout") || iscase("cfs")) M.stuck=1;
    if (iscase("cfs")) M.cfs_on_stuck=1;
    if (iscase("status")) M.inject_sc=0x80;
}
/* Op 9: the engine waits val us of device time. QEMU mode: let QEMU run until idle. C model: add to
 * the model's delay total and, in the slow case, count down the held doorbell and the ready hold.
 * A wait of another length than the engine's two fails the case; a loop of more than ENGINE_POLLS
 * waits ends the run (ENGINE_OVER_BUDGET, exit 2) [ctl:OMEGA-KERNEL-OMEGA-NVME/mutant-budget257]. */
static void engine_wait(uint64_t val)
{
    if (val != ENGINE_READY_WAIT_US && val != ENGINE_CMD_WAIT_US) bad_waits++;
    waits++;
    run_waits++; run_delay += val;
    if (run_waits > ENGINE_POLLS) {
        fprintf(stderr,"FAIL %s: ENGINE_OVER_BUDGET %u waits in one loop, the engine's budget is %u\n",scenario,run_waits,ENGINE_POLLS);
        exit(2);
    }
    if (qfd>=0) { qemu_settle(); return; }
    M.delay_total += val;
    ready_hold_us = ready_hold_us > val ? ready_hold_us - val : 0;
    if (held) {
        hold_us = hold_us > val ? hold_us - val : 0;
        if (!hold_us) { held = 0; m_write32(NULL,held_off,held_val); }
    }
}
/* The engine wrote something (or the run ended): the current wait loop is over. */
static void end_run(void)
{
    if (!run_waits) return;
    if (run_waits > max_waits) { max_waits = run_waits; max_run_delay = run_delay; }
    if (!min_waits || run_waits < min_waits) min_waits = run_waits;
    run_waits = 0; run_delay = 0;
}
static uint64_t access_rpc(uint64_t op,uint64_t addr,uint64_t val)
{
    if (op == 9) { engine_wait(val); return 0; }
    if (op != 1 && op != 2) end_run();
    if (qfd<0 && M.nlog>0 && (iscase("timeout") || iscase("cfs") || iscase("cid") || iscase("sqid") || iscase("phase") || iscase("sqhead"))) {
        check(!(op==5 || (op==3 && addr==0x10000014)), "uncertain DMA is not zeroed/reset/reopened");
    }
    if (qfd>=0) {
        if (op==1) return qt("readl 0x%llx",(unsigned long long)addr);
        if (op==2) return qt("readq 0x%llx",(unsigned long long)addr);
        if (op==3) return qt("writel 0x%llx 0x%llx",(unsigned long long)addr,(unsigned long long)val);
        if (op==4) return qt("writeq 0x%llx 0x%llx",(unsigned long long)addr,(unsigned long long)val);
        if (op==5) return qt("memset 0x%llx %llu 0",(unsigned long long)addr,(unsigned long long)val);
        return 0;
    }
    if (addr>=0x10000000 && addr<0x10010000) {
        uint32_t off=(uint32_t)(addr-0x10000000);
        if (op==1 && off==0x1c && ready_hold_us) return m_read32(NULL,off) & ~1u;
        if (op==1) return m_read32(NULL,off);
        if (op==2) return m_read32(NULL,off)|((uint64_t)m_read32(NULL,off+4)<<32);
        if (op==3 || op==4) {
            check(!held, "no register write while a command is held (slow case)");
            if (iscase("slow") && op==3 && off>=0x1000 && !(((off-0x1000)/stride()) & 1)) {
                held=1; held_off=off; held_val=(uint32_t)val; hold_us=SLOW_CMD_US;
                return 0;
            }
            if (off==0x1008) inject_io();
            m_write32(NULL,off,(uint32_t)val);
            if (iscase("slow") && off==0x14 && (val&1)) ready_hold_us=SLOW_READY_US;
            if (off==0x1008 && (iscase("phase") || iscase("sqhead"))) {
                uint64_t slot=(M.iocq_tail+M.iocq_size-1)%M.iocq_size;
                uint8_t *c=ptr(M.iocq+slot*16,16);
                if (iscase("phase")) p32(c+12,g32(c+12)^(1u<<16));
                else p32(c+8,(g32(c+8)&0xffff0000u)|15);
            }
            if (op==4) m_write32(NULL,off+4,(uint32_t)(val>>32));
            return 0;
        }
    } else if (addr>=PHYS_BASE && addr-PHYS_BASE<DMA_BYTES) {
        uint8_t *p=ptr(addr,op==5?val:op==2||op==4?8:4);
        if (!p) die("model DMA bounds");
        if (op==1) return g32(p);
        if (op==2) return g64(p);
        if (op==3) { p32(p,(uint32_t)val); return 0; }
        if (op==4) { p64(p,val); return 0; }
        if (op==5) { memset(p,0,(size_t)val); return 0; }
    }
    fprintf(stderr,"unsupported RPC %llu %llx\n",(unsigned long long)op,(unsigned long long)addr); exit(2);
}
static void payload(uint64_t addr,uint64_t n)
{
    if (n>8192) die("payload bound");
    uint8_t b[8192];
    if (qfd>=0) {
        /* The engine saw the completion first; QEMU writes the data before it posts that. */
        for (uint64_t i=0;i<n;i+=4) {
            uint32_t v=(uint32_t)qt("readl 0x%llx",(unsigned long long)(addr+i));
            for (uint64_t j=0;j<4 && i+j<n;j++) b[i+j]=(uint8_t)(v>>(j*8));
        }
    } else {
        uint8_t *p=ptr(addr,n); if (!p) die("payload map"); memcpy(b,p,(size_t)n);
        if (M.nadmin==1) {
            memcpy(b+4,"OMEGA-FIXTURE-000001 ",20);
            memcpy(b+64,"8.2.2   ",8);
        }
    }
    if (exact(infd,b,(size_t)n,1)) die("payload send");
}
int main(int argc,char **argv)
{
    if (argc!=3 && argc!=4) { fprintf(stderr,"usage: runner binary case [qemu]\n"); return 2; }
    scenario=argv[2]; atexit(cleanup); signal(SIGPIPE,SIG_IGN);
    if (posix_memalign((void **)&dma_mem,4096,DMA_BYTES)) die("oracle memory");
    model_reset();
    if (iscase("lba4k")) M.lbads=12;
    model_alloc_media(); fill(M.media,(size_t)M.nsze*bsz(),7);
    check(init_default()==NVME_OK,"C oracle initialization");
    check(nvme_read(&C,8,iscase("lba4k")?2:16,expected)==NVME_OK,"C oracle read");
    model_reset();
    if (iscase("lba4k")) M.lbads=12;
    model_alloc_media(); fill(M.media,(size_t)M.nsze*bsz(),7);
    uint8_t manifest[80]={0};
    memcpy(manifest,"OMEGA-FIXTURE-000001 ",20); memcpy(manifest+20,"8.2.2   ",8);
    p32(manifest+28,1); p64(manifest+32,8); p64(manifest+40,64);
    p64(manifest+48,8); p32(manifest+56,16); p32(manifest+60,40); p32(manifest+64,1);
    p64(manifest+72,argc==4?0x40000000:PHYS_BASE);
    int expected_code=0, expected_copies=40, expected_retained=0;
    wanted=8192;
    if (iscase("lba4k")) p32(manifest+56,2);
    if (iscase("singlepage")) { p32(manifest+56,8); wanted=4096; }
    if (iscase("serial")) { manifest[0]^=1; expected_code=21; }
    if (iscase("firmware")) { manifest[20]^=1; expected_code=22; }
    if (iscase("approval")) { p32(manifest+64,0); expected_code=20; }
    if (iscase("nsid")) { p32(manifest+28,2); expected_code=argc==4?25:24; }
    if (iscase("extent")) { p64(manifest+40,4096); expected_code=27; }
    if (iscase("range")) { p64(manifest+48,72); expected_code=31; }
    if (iscase("before")) { p64(manifest+48,7); expected_code=31; }
    if (iscase("prp")) { p32(manifest+56,17); expected_code=30; }
    if (iscase("zero")) { p32(manifest+56,0); expected_code=30; }
    if (iscase("metadata")) { M.ms=8; expected_code=26; }
    if (iscase("format")) { M.lbads=10; expected_code=26; }
    if (iscase("nsze")) { M.nsze=0; expected_code=25; }
    if (iscase("sqes")) { M.sqes=0x55; expected_code=23; }
    if (iscase("cqes")) { M.cqes=0x33; expected_code=23; }
    if (iscase("cap")) { M.cap&=~(1ull<<37); expected_code=28; }
    if (iscase("dstrd")) M.cap|=1ull<<32;
    if (iscase("stride")) { M.cap|=13ull<<32; expected_code=28; }
    if (iscase("readytimeout")) { M.never_ready=1; expected_code=12; expected_retained=1; }
    if (iscase("readycfs")) { M.cfs_on_enable=1; expected_code=11; expected_retained=1; }
    if (iscase("cid")) { expected_code=14; expected_retained=1; }
    if (iscase("sqid")) { expected_code=15; expected_retained=1; }
    if (iscase("timeout")) { expected_code=12; expected_retained=1; }
    if (iscase("cfs")) { expected_code=11; expected_retained=1; }
    if (iscase("phase")) { expected_code=12; expected_retained=1; }
    if (iscase("sqhead")) { expected_code=16; expected_retained=1; }
    if (iscase("status")) expected_code=17;
    if (!strncmp(scenario,"opcode",6)) {
        expected_code=13;
        p32(manifest+60,1);
        p32(manifest+68,(uint32_t)strtoul(scenario+6,NULL,0));
    }
    if (iscase("adminformat")) {
        expected_code=13; p32(manifest+60,0); p32(manifest+68,0x80);
    }
    if (expected_code) expected_copies=0;
    if (argc==4) {
        start_qemu();
        /* QEMU 8.2.2 reports its model firmware as 8.2.2 (space padded). */
    }
    int input[2], output[2]; if (pipe(input)||pipe(output)) die("pipe");
    child=fork(); if (child<0) die("fork candidate");
    if (!child) {
        dup2(input[0],0); dup2(output[1],1);
        close(input[0]); close(input[1]); close(output[0]); close(output[1]);
        execl(argv[1],argv[1],NULL); _exit(127);
    }
    close(input[0]); close(output[1]); infd=input[1]; outfd=output[0];
    if (exact(infd,manifest,sizeof manifest,1)) die("manifest");
    uint8_t request[24], response[8]; unsigned requests=0;
    /* No RPC cap: the engine's loops are bounded by its source (`for i ulong N`, `while ... bound N`),
     * and a wait loop longer than the engine's budget ends the run (engine_wait). */
    while (exact(outfd,request,sizeof request,0)==0) {
        requests++;
        uint64_t op=g64(request),addr=g64(request+8),val=g64(request+16),r=0;
        /* qemukill (control): QEMU killed while the runner waits for it to go idle must end the run at
         * once (QEMU_DEAD, exit 2) [ctl:OMEGA-KERNEL-OMEGA-NVME/qemu-killed]. */
        if (iscase("qemukill") && qfd>=0 && requests==20) {
            kill(qp,SIGKILL);
            qemu_settle();
            fprintf(stderr,"FAIL qemukill: the wait for an idle QEMU returned after QEMU was killed\n");
            exit(1);
        }
        /* qemustop (control): QEMU stopped (SIGSTOP) before this request; the run must end at the next
         * wait on QEMU (QEMU_STOPPED, exit 2) [ctl:OMEGA-KERNEL-OMEGA-NVME/qemu-stopped]. */
        if (iscase("qemustop") && qfd>=0 && requests==20) kill(qp,SIGSTOP);
        if ((op>=1 && op<=5) || op==9) r=access_rpc(op,addr,val);
        else if (op!=6 && op!=7 && op!=8) die("RPC opcode");
        else end_run();
        p64(response,r); if (exact(infd,response,sizeof response,1)) die("RPC response");
        if (op==6) payload(addr,val);
        if (op==7) {
            uint8_t data[8192]; check(val==wanted,"copy-out length");
            if (val>sizeof data || exact(outfd,data,(size_t)val,0)) die("copy-out");
            check(!memcmp(data,expected,(size_t)val),"copy-out equals existing C oracle"); published++;
        }
        if (op==8) { result_code=(int)val; retained=(int)addr; reported++; }
    }
    close(infd); close(outfd);
    end_run();
    /* The candidate closed its output; it exits next. While it works there is no deadline; stopped
     * or idle for a second ends the run (exit 2), and 30 s gets an ALARM line and ends it. */
    int status=0; double since=now_s(), snap=since; struct timespec nap={0,1000000};
    struct idle last = {0,0,0};
    while (waitpid(child,&status,WNOHANG)==0) {
        double t=now_s();
        if (t-snap>=1.0) { candidate_check(); mute_check(child,&last,"and has not exited after closing its output"); snap=t; }
        if (t-since>=ALARM_S) alarm_end("the candidate to exit after closing its output",t-since);
        nanosleep(&nap,NULL);
    }
    child=-1;
    check(WIFEXITED(status) && WEXITSTATUS(status)==expected_code,"candidate exit code");
    check(reported==1 && result_code==expected_code,"reported result");
    check(retained==expected_retained,"timeout/correlation DMA retention");
    check(published==expected_copies,"copy-out only after success");
    if (qfd<0) {
        check(M.protocol_errors==0,"existing C model protocol checks");
        for (int i=0;i<M.nlog && i<MAXLOG;i++) check(M.log[i].opc==2,"NO WRITE OPCODE REACHABLE");
        if (expected_code && expected_code<30 && expected_code!=14 && expected_code!=15 && expected_code!=16 && expected_code!=12 && expected_code!=11 && expected_code!=17 && expected_code!=13)
            check(M.nlog==0,"identity refusal before IO");
        if (!expected_code) { check(M.nlog==40,"IO queue wraps twice"); check(M.last_cq_db[1]==8,"CQ head wraps"); check(M.iocq_phase==1,"CQ phase wraps twice"); }
        if (iscase("adminwrap")) { check(M.nadmin==44,"admin commands wrap twice"); check(M.acq_phase==1 && M.last_cq_db[0]==12,"admin CQ phase/head wrap"); }
    }
    char msg[256];
    if (qfd>=0) {
        qemu_check();
        snprintf(msg,sizeof msg,"QEMU: a wait loop used %u waits, more than QEMU_MAX_WAITS (%u) of the engine's %u",max_waits,QEMU_MAX_WAITS,ENGINE_POLLS);
        check(max_waits<=QEMU_MAX_WAITS,msg);
    }
    snprintf(msg,sizeof msg,"%u transport waits were not the engine's %u or %u us",bad_waits,ENGINE_CMD_WAIT_US,ENGINE_READY_WAIT_US);
    check(bad_waits==0,msg);
    if (iscase("slow")) {
        snprintf(msg,sizeof msg,"slow case: wait loops took %u to %u waits, not exactly the %u the device was held for",min_waits,max_waits,SLOW_HOLD_WAITS);
        check(min_waits==SLOW_HOLD_WAITS && max_waits==SLOW_HOLD_WAITS,msg);
    }
    if (expected_code==12) {
        uint64_t len = iscase("readytimeout") ? ENGINE_READY_WAIT_US : ENGINE_CMD_WAIT_US;
        snprintf(msg,sizeof msg,"timeout case: the longest wait loop took %u waits, %llu us; the engine's budget is %u waits, %llu us",
                 max_waits,(unsigned long long)max_run_delay,ENGINE_POLLS,(unsigned long long)(ENGINE_POLLS*len));
        check(max_waits==ENGINE_POLLS && max_run_delay==ENGINE_POLLS*len,msg);
    }
    check(alarms==0,"no ALARM line (a wait of 30 s or more)");
    printf("%s case=%s transport=%s result=%d copies=%d retained=%d RPC=%u waits=%u maxwait=%u alarms=%d physical=NOT_RUN\n",errors?"FAIL":"PASS",scenario,qfd<0?"C-model":"QEMU",result_code,published,retained,requests,waits,max_waits,alarms);
    free(dma_mem); free(M.media); free(M.cache); free(M.dirty);
    return errors?1:0;
}
