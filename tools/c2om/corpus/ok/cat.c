// copy stdin to stdout, count bytes and lines, exit with the line count
int main(void) {
  int lines = 0;
  int c = getchar();
  while (c != -1) {
    if (c == 10) lines = lines + 1;
    putchar(c);
    c = getchar();
  }
  return lines;
}
