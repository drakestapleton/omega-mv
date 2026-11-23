# Shared GPU completion wait primitive. The C GPU paths link src/omega_gpu_wait.c; its pure OM-2
# port src/omega_gpu_wait.om is tested here with fake memory and a fake clock (the same scenarios,
# test mutants and output as the former C test), plus a naive wall-clock mutant that must be caught.
# Picked up by `-include mk/*.mk`. Host only: opens no device, needs no physics headers, takes no
# chip lock.
GPU_WAIT_OMC ?= seed/out/omc
GPU_WAIT_OM_SRCS := src/omega_gpu_wait.om tests/test_omega_gpu_wait.om
.PHONY: test-gpu-wait
build/test_omega_gpu_wait: $(GPU_WAIT_OM_SRCS) $(GPU_WAIT_OMC)
	@mkdir -p build
	(printf 'om2\n'; sed '/^om2$$/d' $(GPU_WAIT_OM_SRCS)) | $(GPU_WAIT_OMC) > $@ && chmod +x $@
test-gpu-wait: build/test_omega_gpu_wait
	./build/test_omega_gpu_wait

# Real-code mutants: src/omega_gpu_wait.om carries one-line mutant constants. Each copy with one of
# them set to 1 must FAIL the suite; the unedited build must PASS. An edit that changes nothing, or a
# mutant that does not compile, is an error, not a kill.
GPU_WAIT_MUTANTS := OMEGA_GPU_WAIT_MUTANT_STALL_NO_RESET OMEGA_GPU_WAIT_MUTANT_PROGRESS_EXTENDS_HARD OMEGA_GPU_WAIT_MUTANT_NO_READ_BARRIER
.PHONY: test-gpu-wait-mutants
test-gpu-wait-mutants: build/test_omega_gpu_wait
	@./build/test_omega_gpu_wait >/dev/null || { echo "unflagged build FAILED"; exit 1; }
	@echo "unflagged: PASS"
	@set -e; for m in $(GPU_WAIT_MUTANTS); do \
	  sed "s/^const $$m int 0$$/const $$m int 1/" src/omega_gpu_wait.om > build/omega_gpu_wait_$$m.om; \
	  if cmp -s build/omega_gpu_wait_$$m.om src/omega_gpu_wait.om; then echo "MUTANT BROKEN: $$m edit changed nothing"; exit 1; fi; \
	  (printf 'om2\n'; sed '/^om2$$/d' build/omega_gpu_wait_$$m.om tests/test_omega_gpu_wait.om) | $(GPU_WAIT_OMC) > build/test_omega_gpu_wait_$$m; \
	  chmod +x build/test_omega_gpu_wait_$$m; \
	  if ./build/test_omega_gpu_wait_$$m >build/test_omega_gpu_wait_$$m.log 2>&1; then echo "MUTANT SURVIVED: $$m"; exit 1; fi; \
	  echo "$$m: killed ($$(grep -c 'FAIL' build/test_omega_gpu_wait_$$m.log) failing checks)"; \
	done
	@echo "OMEGA_GPU_WAIT_MUTANTS PASS"
