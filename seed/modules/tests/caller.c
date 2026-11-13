/* Independent test oracle, not a production dependency. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
extern uint64_t invoke(void*,void*,void*,uint64_t,uint64_t,uint64_t);
extern void trap_entry(void);
int main(int argc,char **argv) {
 if(argc!=3)return 90;
 int fd=open(argv[1],O_RDONLY); struct stat st;
 if(fd<0||fstat(fd,&st))return 91;
 void *code=mmap(0,st.st_size,PROT_READ|PROT_EXEC,MAP_PRIVATE,fd,0);
 void *stack=mmap(0,8*1024*1024,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
 if(code==MAP_FAILED||stack==MAP_FAILED)return 92;
 uint64_t context[32]={0};context[2]=(uintptr_t)trap_entry;
 uint64_t data[4]={3,5,7,11};
 uint64_t arg=strtoull(argv[2],0,10);
 uint64_t r=invoke(code,(char*)stack+8*1024*1024,context,arg==999?(uintptr_t)data:arg,4,0);
 printf("%llu\n",(unsigned long long)r);return 0;
}
