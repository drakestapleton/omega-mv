/* comparisons as int values, bitwise and/or/xor and their C precedence below equality */
int show(int v) {
  putchar(48 + v / 100 % 10);
  putchar(48 + v / 10 % 10);
  putchar(48 + v % 10);
  putchar(32);
  return 0;
}
int main(void) {
  int a = 12;
  int b = 10;
  int r = show(a & b);
  r = show(a | b);
  r = show(a ^ b);
  r = show(a < b);
  r = show(a > b);
  r = show(a <= 12);
  r = show(a >= 13);
  r = show(a == 12);
  r = show(a != 12);
  r = show((a < b) + (a > b) * 2);
  r = show(a & 4 == 4);
  r = show(1 | 2 ^ 3 & 6);
  r = show(3 < 4 == 1);
  putchar(10);
  return a ^ b;
}
