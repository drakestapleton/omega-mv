// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Times fp8gemv_stream on a machine that has /dev/kfd. bench.sh compiles this
// with hipcc and passes the hsaco path.
//
// Two cache modes, both on this kernel:
//   hot  - warmup launches, then samples, no extra traffic between them
//   cold - a read of a 512 MiB device buffer between samples. 512 MiB is
//          larger than 256 MB, so the read does not fit in the L2 or in a
//          256 MB MALL. hipBLASLt's cold arm calls this same binary with
//          --flush, so both arms take the same read and neither uses
//          hipblaslt-bench --flush (that flag is an instruction-cache flush).
//
// flags bit 0 is the workgroup-to-row remap, not hipBLASLt's tensor swizzle.
// Both settings are checked against the column-order plain reference before
// any sample is timed. The tolerance is check.om's allow() plus the 8 ulps
// of |got|+|plain| from order(). A mismatch prints FAIL and exits non-zero.
//
// SH_MEM_CONFIG bit 8 is SH_MEM_CONFIG__F8_MODE in
// drivers/gpu/drm/amd/include/asic_reg/gc/gc_9_4_3_sh_mask.h (shift 0x8,
// mask 0x00000100). Alignment mode is bits 4:3. RETRY_DISABLE is bit 12.
// KFD sets F8_MODE for GC 9.4.3. This code object does not write the register.
// See the README for the file and field citations.

#include "plain_ref.h"

#include <hip/hip_runtime.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

constexpr double kPeakBytesPerSec = 5.3e12;
constexpr int kWarmup = 10;
constexpr int kRuns = 21;
constexpr size_t kFlushBytes = 512ull << 20;
constexpr int kFlushBlocks = 2048;

struct alignas(8) Args {
  uint64_t w;
  uint64_t x;
  uint64_t scale;
  uint64_t y;
  uint64_t residual;
  uint64_t gamma;
  float inv_rms;
  uint32_t m;
  uint32_t k;
  uint32_t flags;
};

static_assert(sizeof(Args) == 64, "kernarg is 64 bytes");
static_assert(offsetof(Args, inv_rms) == 48, "inv_rms offset");
static_assert(offsetof(Args, flags) == 60, "flags offset");

#define CHECK(cmd)                                                             \
  do {                                                                         \
    hipError_t err_ = (cmd);                                                   \
    if (err_ != hipSuccess) {                                                  \
      std::fprintf(stderr, "%s: %s\n", #cmd, hipGetErrorString(err_));         \
      return 1;                                                                \
    }                                                                          \
  } while (0)

}  // namespace

__global__ void flush_l2(const uint32_t* p, size_t n, uint32_t* sink) {
  size_t stride = static_cast<size_t>(gridDim.x) * blockDim.x;
  uint32_t acc = 0;
  for (size_t i = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
       i < n; i += stride) {
    acc += p[i];
  }
  sink[blockIdx.x] = acc;
}

namespace {

int launch(hipFunction_t fn, Args args, uint32_t grid, hipEvent_t start,
           hipEvent_t stop, float* ms) {
  size_t bytes = sizeof(args);
  void* extra[] = {HIP_LAUNCH_PARAM_BUFFER_POINTER, &args,
                   HIP_LAUNCH_PARAM_BUFFER_SIZE, &bytes, HIP_LAUNCH_PARAM_END};
  CHECK(hipEventRecord(start));
  CHECK(hipModuleLaunchKernel(fn, grid, 1, 1, 64, 1, 1, 0, nullptr, nullptr,
                              extra));
  CHECK(hipEventRecord(stop));
  CHECK(hipEventSynchronize(stop));
  CHECK(hipEventElapsedTime(ms, start, stop));
  return 0;
}

int flush_cache(uint32_t* buf, uint32_t* sink) {
  size_t n = kFlushBytes / sizeof(uint32_t);
  flush_l2<<<kFlushBlocks, 256>>>(buf, n, sink);
  CHECK(hipGetLastError());
  CHECK(hipDeviceSynchronize());
  return 0;
}

uint64_t xorshift(uint64_t x) {
  x ^= x << 13;
  x ^= x >> 7;
  x ^= x << 17;
  return x;
}

}  // namespace

int main(int argc, char** argv) {
  bool flush_only = argc == 2 && std::strcmp(argv[1], "--flush") == 0;
  if (!flush_only && argc != 2) {
    std::fprintf(stderr, "usage: time_fp8gemv fp8gemv_stream.hsaco\n");
    std::fprintf(stderr, "       time_fp8gemv --flush\n");
    return 2;
  }

  int device = 0;
  CHECK(hipGetDeviceCount(&device));
  if (device < 1) {
    std::fprintf(stderr, "BLOCKED_HARDWARE hipGetDeviceCount returned 0\n");
    return 1;
  }
  CHECK(hipSetDevice(0));
  hipDeviceProp_t prop{};
  CHECK(hipGetDeviceProperties(&prop, 0));
  int runtime = 0;
  CHECK(hipRuntimeGetVersion(&runtime));
  std::printf("device %s gcn %s pci %04x:%02x:%02x\n", prop.name, prop.gcnArchName,
              prop.pciDomainID, prop.pciBusID, prop.pciDeviceID);
  std::printf("hip %d clock_kHz %d mem_clock_kHz %d\n", runtime, prop.clockRate,
              prop.memoryClockRate);
  std::printf(
      "sh_mem F8_MODE is bit 8 of SH_MEM_CONFIG (gc_9_4_3_sh_mask.h "
      "SH_MEM_CONFIG__F8_MODE). KFD sets it for GC 9.4.3. This code object "
      "does not.\n");

  uint32_t* flush_buf = nullptr;
  uint32_t* flush_sink = nullptr;
  CHECK(hipMalloc(&flush_buf, kFlushBytes));
  CHECK(hipMalloc(&flush_sink, static_cast<size_t>(kFlushBlocks) * sizeof(uint32_t)));
  CHECK(hipMemset(flush_buf, 1, kFlushBytes));
  if (flush_cache(flush_buf, flush_sink)) return 1;
  std::printf("flush_bytes %zu\n", kFlushBytes);
  if (flush_only) return 0;

  hipModule_t mod{};
  CHECK(hipModuleLoad(&mod, argv[1]));
  hipFunction_t fn{};
  hipError_t got_fn = hipModuleGetFunction(&fn, mod, "fp8gemv_stream");
  if (got_fn != hipSuccess) {
    std::fprintf(stderr, "hipModuleGetFunction(fp8gemv_stream): %s\n",
                 hipGetErrorString(got_fn));
    return 1;
  }

  const uint32_t rows[] = {4096, 8192, 14336, 28672};
  const uint32_t cols[] = {4096, 8192};
  uint64_t biggest = 0;
  for (uint32_t m : rows) {
    for (uint32_t k : cols) {
      biggest = std::max(biggest, static_cast<uint64_t>(m) * k);
    }
  }
  uint32_t max_m = rows[sizeof(rows) / sizeof(rows[0]) - 1];
  uint32_t max_k = cols[sizeof(cols) / sizeof(cols[0]) - 1];

  void* w = nullptr;
  void* x = nullptr;
  void* scale = nullptr;
  void* y = nullptr;
  void* residual = nullptr;
  void* gamma = nullptr;
  CHECK(hipMalloc(&w, biggest));
  CHECK(hipMalloc(&x, static_cast<size_t>(max_k) * sizeof(float)));
  CHECK(hipMalloc(&scale, static_cast<size_t>(max_m) * sizeof(float)));
  CHECK(hipMalloc(&y, static_cast<size_t>(max_m) * sizeof(float)));
  CHECK(hipMalloc(&residual, static_cast<size_t>(max_m) * sizeof(float)));
  CHECK(hipMalloc(&gamma, static_cast<size_t>(max_m) * sizeof(float)));

  std::vector<uint8_t> host_w(biggest);
  uint64_t xs = 1;
  for (uint64_t i = 0; i < biggest; ++i) {
    xs = xorshift(xs);
    uint8_t b = static_cast<uint8_t>(xs & 0xffu);
    if (b == 0x80) b = 0x7f;
    host_w[i] = b;
  }
  std::vector<uint32_t> host_x(max_k, 0x3f800000u);
  std::vector<uint32_t> host_scale(max_m, 0x3f800000u);
  CHECK(hipMemcpy(w, host_w.data(), biggest, hipMemcpyHostToDevice));
  CHECK(hipMemcpy(x, host_x.data(), host_x.size() * sizeof(uint32_t),
                  hipMemcpyHostToDevice));
  CHECK(hipMemcpy(scale, host_scale.data(), host_scale.size() * sizeof(uint32_t),
                  hipMemcpyHostToDevice));

  hipEvent_t start{};
  hipEvent_t stop{};
  CHECK(hipEventCreate(&start));
  CHECK(hipEventCreate(&stop));

  std::printf("kernel_bytes M*K+4*K+8*M\n");
  std::printf("peak denominator %.1f TB/s published\n", kPeakBytesPerSec / 1e12);

  struct Shape {
    uint32_t m;
    uint32_t k;
    uint32_t swizzle;
    uint32_t grid;
    Args args;
  };
  std::vector<Shape> shapes;
  for (uint32_t m : rows) {
    for (uint32_t k : cols) {
      for (uint32_t swizzle : {0u, 1u}) {
        uint32_t span = (m + 7u) >> 3;
        Shape s;
        s.m = m;
        s.k = k;
        s.swizzle = swizzle;
        s.grid = swizzle ? span * 8u : m;
        s.args = Args{};
        s.args.w = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(w));
        s.args.x = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(x));
        s.args.scale = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(scale));
        s.args.y = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(y));
        s.args.residual =
            static_cast<uint64_t>(reinterpret_cast<uintptr_t>(residual));
        s.args.gamma = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(gamma));
        s.args.inv_rms = 1.0f;
        s.args.m = m;
        s.args.k = k;
        s.args.flags = swizzle;
        shapes.push_back(s);
      }
    }
  }

  for (const Shape& s : shapes) {
    CHECK(hipMemset(y, 0, static_cast<size_t>(s.m) * sizeof(float)));
    float ms = 0.f;
    if (launch(fn, s.args, s.grid, start, stop, &ms)) return 1;
    std::vector<uint32_t> got(s.m);
    CHECK(hipMemcpy(got.data(), y, got.size() * sizeof(uint32_t),
                    hipMemcpyDeviceToHost));
    for (uint32_t row = 0; row < s.m; ++row) {
      PlainRow plain = plain_row(host_w.data() + static_cast<uint64_t>(row) * s.k,
                                 host_x.data(), s.k, host_scale[row]);
      uint32_t bound =
          tolerance_bits(plain.sumabs, s.k, host_scale[row], got[row], plain.bits);
      if (!within_plain(got[row], plain.bits, bound)) {
        std::printf(
            "FAIL M %u K %u swizzle %u row %u got %08x plain %08x bound %08x\n",
            s.m, s.k, s.swizzle, row, got[row], plain.bits, bound);
        std::fprintf(stderr,
                     "FAIL M %u K %u swizzle %u row %u got %08x plain %08x bound %08x\n",
                     s.m, s.k, s.swizzle, row, got[row], plain.bits, bound);
        return 1;
      }
    }
    std::printf("check M %u K %u swizzle %u PASS\n", s.m, s.k, s.swizzle);
  }
  std::printf("device check PASS\n");

  const char* modes[] = {"hot", "cold"};
  for (const char* mode : modes) {
    bool cold = std::strcmp(mode, "cold") == 0;
    int warmup = cold ? 0 : kWarmup;
    for (const Shape& s : shapes) {
      float ms = 0.f;
      for (int i = 0; i < warmup; ++i) {
        if (launch(fn, s.args, s.grid, start, stop, &ms)) return 1;
      }
      std::vector<double> us;
      us.reserve(kRuns);
      for (int i = 0; i < kRuns; ++i) {
        if (cold && flush_cache(flush_buf, flush_sink)) return 1;
        if (launch(fn, s.args, s.grid, start, stop, &ms)) return 1;
        us.push_back(static_cast<double>(ms) * 1000.0);
      }
      std::vector<double> sorted = us;
      std::sort(sorted.begin(), sorted.end());
      double med = sorted[sorted.size() / 2];
      double lo = sorted.front();
      double hi = sorted.back();
      double bytes = static_cast<double>(s.m) * s.k + 4.0 * s.k + 8.0 * s.m;
      double gbps = bytes / (med * 1e-6) / 1e9;
      double pct = (bytes / (med * 1e-6)) / kPeakBytesPerSec * 100.0;
      std::printf(
          "kernel_swizzle %u mode %s M %u K %u grid %u warmup %d runs %d "
          "min_us %.4f median_us %.4f max_us %.4f spread_us %.4f bytes %.0f "
          "GB/s %.4f pct_of_5.3TBs %.4f\n",
          s.swizzle, mode, s.m, s.k, s.grid, warmup, kRuns, lo, med, hi, hi - lo,
          bytes, gbps, pct);
      std::printf("samples_us");
      for (double sample : us) std::printf(" %.4f", sample);
      std::printf("\n");
    }
  }
  return 0;
}
