/* classify input bytes without arrays: counts of digits, letters, spaces, other; exit = other */
int isdigit_(int c) { return c >= 48 & c <= 57; }
int isalpha_(int c) { return (c >= 65 & c <= 90) | (c >= 97 & c <= 122); }
int put2(int v) {
  int hi = v / 10 % 10;
  putchar(48 + hi);
  putchar(48 + v % 10);
  putchar(32);
  return 0;
}
int main(void) {
  int d = 0;
  int a = 0;
  int s = 0;
  int o = 0;
  int c = getchar();
  while (c != -1) {
    int isd = isdigit_(c);
    if (isd) {
      d = d + 1;
    } else {
      int isa = isalpha_(c);
      if (isa) a = a + 1;
      else if (c == 32 | c == 10) s = s + 1;
      else o = o + 1;
    }
    c = getchar();
  }
  int r = put2(d);
  r = put2(a);
  r = put2(s);
  r = put2(o);
  putchar(10);
  return o;
}
