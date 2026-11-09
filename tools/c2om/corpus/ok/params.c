/* six parameters, nested calls in separate statements, if/else chains, blocks */
int mix(int a, int b, int c, int d, int e, int f) {
  return a * 100000 + b * 10000 + c * 1000 + d * 100 + e * 10 + f;
}
int sign(int x) {
  if (x < 0) {
    return -1;
  } else if (x == 0) {
    return 0;
  } else {
    return 1;
  }
}
int digits(int v) {
  int n = 0;
  if (v == 0) return 1;
  while (v != 0) {
    v = v / 10;
    n = n + 1;
  }
  return n;
}
int main(void) {
  int m = mix(1, 2, 3, 4, 5, 6);
  int s = sign(m - 123456);
  int t = sign(-m);
  int k = digits(m);
  putchar(48 + s);
  putchar(48 + t + 2);
  putchar(48 + k);
  putchar(10);
  return m % 256;
}
