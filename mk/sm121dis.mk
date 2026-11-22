# C6 of docs/OMEGA.md: Omega's own sm_121 disassembler (gpu/nvidia/om/disasm/sm121_dis.om, tools/sm121dis/sm121dis.om).
#   make test-sm121dis   collect every kernel the library builds (no GPU), compare our text with nvdisasm's, word by word;
#                        then the red check: a decoder built with one deliberate fault must FAIL the same comparison.
# Picked up by the `-include mk/*.mk` line of the Makefile. The test binaries are named as files, not through the
# GPU_*_TEST variables: this file is read before the Makefile defines them.
SM121DIS = $(OUT_DIR)/sm121dis
SM121DIS_RED = $(OUT_DIR)/sm121dis_red
SM121DIS_K = $(OUT_DIR)/sm121dis-kernels

$(SM121DIS): gpu/nvidia/om/disasm/sm121_dis.om tools/sm121dis/sm121dis.om seed/out/omc
	@mkdir -p $(OUT_DIR)
	cat gpu/nvidia/om/disasm/sm121_dis.om tools/sm121dis/sm121dis.om | seed/out/omc > $@ && chmod +x $@
$(SM121DIS_RED): gpu/nvidia/om/disasm/sm121_dis.om tools/sm121dis/sm121dis.om seed/out/omc
	@mkdir -p $(OUT_DIR)
	{ cat gpu/nvidia/om/disasm/sm121_dis.om; sed 's/cli_oc get tbuf i/cli_oc xor get tbuf i 1/' tools/sm121dis/sm121dis.om; } | seed/out/omc > $@ && chmod +x $@

sm121dis-corpus-bins: $(addprefix $(OUT_DIR)/,gpu_matmul_api_test gpu_elementwise_test gpu_reconv_test gpu_attention_test \
	gpu_moe_window_test gpu_fp8_api_test gpu_decode_attn_test gpu_router_test gpu_bf16_gemv_test gpu_tern_test gpu_fp8gemm_test \
	gpu_tc_probe_test gpu_tc_peak_test gpu_pf_mem_test gpu_qmma_probe_test gpu_cmdlist_test gpu_decode_graph_test gpu_tcgemm_test \
	gpu_prefill_attn_test gpu_pfgemm_test gpu_qgemm_test gpu_pfhost_test gpu_gpr_boundary_test \
	gpu_scan_test gpu_gemm_test gpu_streams_test gpu_isolation_test bw_hazard_test) \
	build/test_omega_divsqrt_gb10_cpu build/test_omega_ldst_gb10_cpu

.PHONY: test-sm121dis sm121dis-corpus-bins test-sm121dis-corpus-controls test-sm121dis-check-controls
test-sm121dis-corpus-controls:
	sh tools/sm121dis/corpus_selftest.sh

test-sm121dis-check-controls:
	sh tools/sm121dis/check_selftest.sh

test-sm121dis: $(SM121DIS) $(SM121DIS_RED) sm121dis-corpus-bins test-sm121dis-corpus-controls test-sm121dis-check-controls
	rm -rf $(SM121DIS_K) && sh tools/sm121dis/corpus.sh $(OUT_DIR) $(SM121DIS_K)
	sh tools/sm121dis/check.sh $(SM121DIS) $(SM121DIS_K) $(OUT_DIR)/sm121dis-work
	@if sh tools/sm121dis/check.sh $(SM121DIS_RED) $(SM121DIS_K) $(OUT_DIR)/sm121dis-red > $(OUT_DIR)/sm121dis-red.log 2>&1; then \
		echo "RED CHECK BROKEN: the faulty decoder passed"; exit 1; \
	elif ! grep -q '^VERDICT FAIL' $(OUT_DIR)/sm121dis-red.log; then \
		echo "RED CHECK BROKEN: the faulty decoder's run did not reach a verdict"; tail -3 $(OUT_DIR)/sm121dis-red.log; exit 1; \
	else echo "red check: the faulty decoder FAILS the comparison, as it must ($$(grep -c '^\[FAIL\]' $(OUT_DIR)/sm121dis-red.log) kernels)"; fi

# The provenance checks (tools/divsqrt_nvdisasm_check.sh, tools/ldst_nvdisasm_check.sh, test-numeric-reduce-nvdisasm)
# call build/sm121dis by that name, whatever OUT_DIR is.
ifneq ($(OUT_DIR),build)
build/sm121dis: gpu/nvidia/om/disasm/sm121_dis.om tools/sm121dis/sm121dis.om seed/out/omc
	@mkdir -p build
	cat gpu/nvidia/om/disasm/sm121_dis.om tools/sm121dis/sm121dis.om | seed/out/omc > $@ && chmod +x $@
endif

# ZERO-NVDISASM (bar C6, second half: nothing calls nvdisasm). tools/sm121dis/zero_nvdisasm.sh runs every listing and
# provenance check with a decoy nvdisasm first on PATH, the CUDA directories removed from PATH, and strace on execve;
# then its own red check plants two calls to nvdisasm and must see the gate FAIL.
.PHONY: test-zero-nvdisasm
test-zero-nvdisasm: $(SM121DIS) build/sm121dis build/test_omega_reduce_cpu $(addprefix $(OUT_DIR)/,gpu_attention_test gpu_elementwise_test gpu_fp8_api_test gpu_reconv_test bw_hazard_test)
	PHYSICS_DIR="$(PHYSICS_DIR)" sh tools/sm121dis/zero_nvdisasm.sh $(OUT_DIR)
	@if PHYSICS_DIR="$(PHYSICS_DIR)" sh tools/sm121dis/zero_nvdisasm.sh $(OUT_DIR) --red > $(OUT_DIR)/zero-nvdisasm-red.log 2>&1; then \
		echo "RED CHECK BROKEN: the planted nvdisasm calls passed the gate"; exit 1; \
	else echo "red check: the planted nvdisasm calls FAIL the gate, as they must ($$(grep -c 'FAIL$$' $(OUT_DIR)/zero-nvdisasm-red.log) lines)"; fi
