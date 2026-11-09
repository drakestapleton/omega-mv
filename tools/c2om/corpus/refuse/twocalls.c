int one(void) { return 1; }
int main(void) {
  int x = one() + one();
  return x;
}
