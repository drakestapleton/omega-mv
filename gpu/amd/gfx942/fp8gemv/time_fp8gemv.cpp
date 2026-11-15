// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Times fp8gemv_stream on a machine that has /dev/kfd. bench.sh compiles this
// with hipcc and passes the hsaco path. Two arms: flags bit 0 clear, then set.
// That bit is the workgroup-to-row remap, not hipBLASLt's tensor swizzle.
//
// CDNA3 ISA 7.2: SH_MEM_CONFIG bit 8 must be 1 or the FP8 convert does not use
// this format. This code object does not write that register.

#include <hip/hip_runtime.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

namespace {

constexpr double kPeakBytesPerSec = 5.3e12;
constexpr int kWarmup = 10;
constexpr int kRuns = 21;

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

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: time_fp8gemv fp8gemv_stream.hsaco\n");
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
      "SH_MEM_CONFIG bit 8 is not set by this code object; ISA 7.2 requires it for FP8\n");

  hipModule_t mod{};
  CHECK(hipModuleLoad(&mod, argv[1]));
  hipFunction_t fn{};
  hipError_t got = hipModuleGetFunction(&fn, mod, "fp8gemv_stream");
  if (got != hipSuccess) {
    std::fprintf(stderr, "hipModuleGetFunction(fp8gemv_stream): %s\n",
                 hipGetErrorString(got));
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

  void* w = nullptr;
  void* x = nullptr;
  void* scale = nullptr;
  void* y = nullptr;
  void* residual = nullptr;
  void* gamma = nullptr;
  CHECK(hipMalloc(&w, biggest));
  CHECK(hipMalloc(&x, static_cast<size_t>(cols[1]) * sizeof(float)));
  CHECK(hipMalloc(&scale, static_cast<size_t>(max_m) * sizeof(float)));
  CHECK(hipMalloc(&y, static_cast<size_t>(max_m) * sizeof(float)));
  CHECK(hipMalloc(&residual, static_cast<size_t>(max_m) * sizeof(float)));
  CHECK(hipMalloc(&gamma, static_cast<size_t>(max_m) * sizeof(float)));
  CHECK(hipMemset(w, 0x40, biggest));
  CHECK(hipMemset(x, 0, static_cast<size_t>(cols[1]) * sizeof(float)));
  CHECK(hipMemset(scale, 0, static_cast<size_t>(max_m) * sizeof(float)));

  std::vector<float> ones(std::max<uint32_t>(max_m, cols[1]), 1.0f);
  CHECK(hipMemcpy(x, ones.data(), static_cast<size_t>(cols[1]) * sizeof(float),
                  hipMemcpyHostToDevice));
  CHECK(hipMemcpy(scale, ones.data(), static_cast<size_t>(max_m) * sizeof(float),
                  hipMemcpyHostToDevice));

  hipEvent_t start{};
  hipEvent_t stop{};
  CHECK(hipEventCreate(&start));
  CHECK(hipEventCreate(&stop));

  std::printf(
      "bytes are M*K weights + 4*K activations + 4*M scale + 4*M store\n");
  std::printf("peak denominator %.1f TB/s\n", kPeakBytesPerSec / 1e12);

  for (uint32_t m : rows) {
    for (uint32_t k : cols) {
      for (uint32_t swizzle : {0u, 1u}) {
        uint32_t span = (m + 7u) >> 3;
        uint32_t grid = swizzle ? span * 8u : m;
        Args args{};
        args.w = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(w));
        args.x = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(x));
        args.scale = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(scale));
        args.y = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(y));
        args.residual = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(residual));
        args.gamma = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(gamma));
        args.inv_rms = 1.0f;
        args.m = m;
        args.k = k;
        args.flags = swizzle;
        float ms = 0.0f;
        for (int i = 0; i < kWarmup; ++i) {
          if (launch(fn, args, grid, start, stop, &ms)) return 1;
        }
        std::vector<double> us;
        us.reserve(kRuns);
        for (int i = 0; i < kRuns; ++i) {
          if (launch(fn, args, grid, start, stop, &ms)) return 1;
          us.push_back(static_cast<double>(ms) * 1000.0);
        }
        std::vector<double> sorted = us;
        std::sort(sorted.begin(), sorted.end());
        double med = sorted[sorted.size() / 2];
        double lo = sorted.front();
        double hi = sorted.back();
        double bytes = static_cast<double>(m) * k + 4.0 * k + 8.0 * m;
        double gbps = bytes / (med * 1e-6) / 1e9;
        double pct = (bytes / (med * 1e-6)) / kPeakBytesPerSec * 100.0;
        std::printf(
            "kernel_swizzle %u M %u K %u grid %u warmup %d runs %d min_us %.4f "
            "median_us %.4f max_us %.4f spread_us %.4f bytes %.0f GB/s %.4f "
            "pct_of_5.3TBs %.4f\n",
            swizzle, m, k, grid, kWarmup, kRuns, lo, med, hi, hi - lo, bytes,
            gbps, pct);
        std::printf("samples_us");
        for (double sample : us) std::printf(" %.4f", sample);
        std::printf("\n");
      }
    }
  }
  return 0;
}
