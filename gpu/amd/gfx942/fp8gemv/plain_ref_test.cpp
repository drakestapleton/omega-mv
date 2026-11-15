// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Locks plain_ref.h to bit patterns check.om already accepts. A drift here
// fails check.sh before any device is involved.

#include "plain_ref.h"

#include <cstdio>
#include <cstdint>
#include <vector>

namespace {

int fails = 0;

void expect(const char* name, uint32_t got, uint32_t want) {
  if (got == want) return;
  std::fprintf(stderr, "FAIL %s got %08x want %08x\n", name, got, want);
  fails += 1;
}

void expect_true(const char* name, bool ok) {
  if (ok) return;
  std::fprintf(stderr, "FAIL %s\n", name);
  fails += 1;
}

}  // namespace

int main() {
  expect("fnuz 0x40", fnuz_bits(0x40), 0x3f800000u);
  expect("fnuz 0x00", fnuz_bits(0x00), 0);
  expect("fnuz 0x80", fnuz_bits(0x80), 0x7fc00000u);
  expect("fnuz 0x01", fnuz_bits(0x01), 0x3a800000u);
  expect("fnuz 0x81", fnuz_bits(0x81), 0xba800000u);
  expect("fnuz 0xC0", fnuz_bits(0xc0), 0xbf800000u);
  expect("fnuz 0xFF", fnuz_bits(0xff), 0xc3700000u);
  expect("fnuz 0x7F", fnuz_bits(0x7f), 0x43700000u);
  expect("i2f 1", i2f_bits(1), 0x3f800000u);
  expect("i2f 17", i2f_bits(17), 0x41880000u);
  expect("i2f 1026", i2f_bits(1026), 0x44804000u);

  const uint32_t one = 0x3f800000u;
  std::vector<uint8_t> w(32, 0);
  std::vector<uint32_t> x(32, 0);

  w[0] = 0x40;
  x[0] = one;
  expect("K=1", plain_row(w.data(), x.data(), 1, one).bits, 0x3f800000u);

  for (int i = 0; i < 16; ++i) {
    w[i] = 0x40;
    x[i] = one;
  }
  expect("K=16", plain_row(w.data(), x.data(), 16, one).bits, 0x41800000u);
  w[16] = 0x40;
  x[16] = one;
  expect("K=17", plain_row(w.data(), x.data(), 17, one).bits, 0x41880000u);

  w.assign(32, 0);
  x.assign(32, 0);
  w[0] = 0xff;
  x[0] = one;
  expect("0xFF", plain_row(w.data(), x.data(), 1, one).bits, 0xc3700000u);
  w[0] = 0x80;
  expect("0x80", plain_row(w.data(), x.data(), 1, one).bits, 0x7fc00000u);
  w[0] = 0x7f;
  x[0] = 0x7c800000u;
  expect("240*2^122", plain_row(w.data(), x.data(), 1, one).bits, 0x7f800000u);

  w.assign(32, 0);
  x.assign(32, 0);
  w[0] = 0x40;
  x[0] = 0x49800000u;
  w[1] = 0x40;
  x[1] = 0x3a800000u;
  w[16] = 0xc0;
  x[16] = 0x49800000u;
  w[17] = 0x40;
  x[17] = 0x3a800000u;
  PlainRow cancel = plain_row(w.data(), x.data(), 32, one);
  expect("cancel plain", cancel.bits, 0x3a800000u);
  uint32_t bound = tolerance_bits(cancel.sumabs, 32, one, 0, cancel.bits);
  expect_true("cancel kernel 0 is inside the bound",
              within_plain(0, cancel.bits, bound));

  w.assign(1, 0x40);
  x.assign(1, one);
  PlainRow k1 = plain_row(w.data(), x.data(), 1, one);
  uint32_t tight = tolerance_bits(k1.sumabs, 1, one, k1.bits, k1.bits);
  expect_true("K=1 rejects a result of 0",
              !within_plain(0, k1.bits, tight));
  expect_true("K=1 accepts itself",
              within_plain(k1.bits, k1.bits, tight));
  expect_true("nonfinite mismatch fails",
              !within_plain(0x7f800000u, 0x3f800000u, tight));
  expect_true("matching inf passes",
              within_plain(0x7f800000u, 0x7f800000u, tight));

  if (fails) {
    std::printf("FAIL\n");
    return 1;
  }
  std::printf("plain ref pass\n");
  return 0;
}
