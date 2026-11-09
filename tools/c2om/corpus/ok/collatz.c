/* longest Collatz chain under a bound read as decimal from stdin (default 1000) */
int steps(int n) {
  int k = 0;
  while (n != 1) {
    if (n % 2 == 0) n = n / 2;
    else n = 3 * n + 1;
    k = k + 1;
  }
  return k;
}
int readnum(void) {
  int v = 0;
  int seen = 0;
  int c = getchar();
  while (c >= 48 & c <= 57) {
    v = v * 10 + c - 48;
    seen = 1;
    c = getchar();
  }
  if (!seen) return 1000;
  return v;
}
int show(int v) {
  int d = 1;
  while (v / d >= 10) d = d * 10;
  while (d > 0) {
    putchar(48 + v / d % 10);
    d = d / 10;
  }
  return 0;
}
int main(void) {
  int limit = readnum();
  int best = 1;
  int bestk = 0;
  int i = 1;
  while (i < limit) {
    int k = steps(i);
    if (k > bestk) {
      bestk = k;
      best = i;
    }
    i = i + 1;
  }
  int r = show(best);
  putchar(32);
  r = show(bestk);
  putchar(10);
  return 0;
}
