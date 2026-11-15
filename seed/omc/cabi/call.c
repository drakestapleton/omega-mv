int add2(int a, int b) { return a + b; }
long addl(long a, long b) { return a + b; }
int pick(int *p) { return p[0] + p[1]; }

extern int om_add(int a, int b);
extern long om_addl(long a, long b);
extern int om_pick(int *p);
extern int om_sum6(int a, int b, int c, int d, int e, int f);
extern int om_call(void);

int main(void) {
    int xs[2];
    xs[0] = 3;
    xs[1] = 4;
    if (om_add(20, 22) != 42) return 1;
    if (om_add(0, -5) != -5) return 2;
    if (om_addl(100, 23) != 123) return 3;
    if (om_pick(xs) != 7) return 4;
    if (om_sum6(1, 2, 3, 4, 5, 6) != 21) return 5;
    if (om_call() != 0) return 6;
    return 0;
}
