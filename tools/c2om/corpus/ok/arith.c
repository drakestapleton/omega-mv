/* signed division and remainder toward zero, unary operators, precedence */
int show(int v) {
  if (v < 0) {
    putchar(45);
    v = -v;
  }
  int d = 1;
  while (v / d >= 10) d = d * 10;
  while (d > 0) {
    putchar(48 + v / d % 10);
    d = d / 10;
  }
  putchar(32);
  return 0;
}
int main(void) {
  int r = show(7 / 2);
  r = show(-7 / 2);
  r = show(7 / -2);
  r = show(-7 % 3);
  r = show(7 % -3);
  r = show(2 + 3 * 4 - 5);
  r = show((2 + 3) * (4 - 5));
  r = show(10 - 4 - 3);
  r = show(100 / 10 / 5);
  r = show(-(-5));
  r = show(+9);
  r = show(!0);
  r = show(!7);
  r = show(~5);
  r = show(~-1);
  r = show(2147483647);
  r = show(-2147483647 - 1 + 1);
  putchar(10);
  return 0;
}
