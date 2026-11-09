/* recursion, locals, digit printing; exit status is the first input byte or -1 */
int fib(int n) {
  if (n < 2) return n;
  int a = fib(n - 1);
  int b = fib(n - 2);
  return a + b;
}
int main(void) {
  int c = getchar();
  int x = fib(24);
  while (x != 0) {
    putchar(48 + x % 10);
    x = x / 10;
  }
  putchar(10);
  return c;
}
