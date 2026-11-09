#include <stdio.h>
static unsigned long long fib(unsigned long long n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
int main(void) { printf("%llu\n", fib(40)); return 0; }
