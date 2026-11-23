# Differential qualification of the pure OM-2 GPU completion wait src/omega_gpu_wait.om against the
# live C primitive src/omega_gpu_wait.c it ports (identical at main commit 3f2c70dc5 and here).
# Host only, CPU only, opens no device, needs no C compiler.
#
# test-gpu-wait-parity
#   1. tests/gpu_wait_parity.sh: the hand and random scripted scenarios through
#      tests/gpu_wait_dump.om (built with the shipped src/omega_gpu_wait.om), byte for byte against
#      the committed goldens of the C at main 3f2c70dc5 (tests/gpu_wait_golden, MANIFEST with
#      commit, generator and sha256): return value, every report field, hook call counts and order;
#   2. tests/gpu_wait_mutants.sh: every mutant of omega_gpu_wait.om must differ from the goldens.
.PHONY: test-gpu-wait-parity
test-gpu-wait-parity: $(GPU_WAIT_OMC)
	GPU_WAIT_PARITY_WORK=$(abspath $(OUT_DIR))/gpu-wait-parity sh tests/gpu_wait_parity.sh $(abspath $(GPU_WAIT_OMC))
	GPU_WAIT_PARITY_WORK=$(abspath $(OUT_DIR))/gpu-wait-parity sh tests/gpu_wait_mutants.sh $(abspath $(GPU_WAIT_OMC))
