# Shared GPU completion wait primitive (src/omega_gpu_wait.c, linked by the C GPU paths): host unit
# test with fake memory and a fake clock, plus a naive wall-clock mutant that must be caught. The same
# test runs on the live C primitive and on its pure OM-2 port src/omega_gpu_wait.om. Picked up by
# `-include mk/*.mk`. Host only: opens no device, needs no physics headers, takes no chip lock.
GPU_WAIT_OMC ?= seed/out/omc
GPU_WAIT_OM_SRCS := src/omega_gpu_wait.om tests/test_omega_gpu_wait.om
.PHONY: test-gpu-wait
build/test_omega_gpu_wait: tests/test_omega_gpu_wait.c src/omega_gpu_wait.c src/omega_gpu_wait.h
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -D_GNU_SOURCE -Isrc -o $@ tests/test_omega_gpu_wait.c src/omega_gpu_wait.c
build/test_omega_gpu_wait_om: $(GPU_WAIT_OM_SRCS) $(GPU_WAIT_OMC)
	@mkdir -p build
	(printf 'om2\n'; sed '/^om2$$/d' $(GPU_WAIT_OM_SRCS)) | $(GPU_WAIT_OMC) > $@ && chmod +x $@
test-gpu-wait: build/test_omega_gpu_wait build/test_omega_gpu_wait_om
	./build/test_omega_gpu_wait
	./build/test_omega_gpu_wait_om

# Real-code mutants: src/omega_gpu_wait.c carries one-line compile-flag mutants and
# src/omega_gpu_wait.om the same three as one-line constants. Each flagged C build and each .om copy
# with one constant set to 1 must FAIL the suite; the unflagged builds must PASS. A mutant that does
# not compile, or an .om edit that changes nothing, is an error, not a kill.
GPU_WAIT_MUTANTS := OMEGA_GPU_WAIT_MUTANT_STALL_NO_RESET OMEGA_GPU_WAIT_MUTANT_PROGRESS_EXTENDS_HARD OMEGA_GPU_WAIT_MUTANT_NO_READ_BARRIER
.PHONY: test-gpu-wait-mutants
test-gpu-wait-mutants: build/test_omega_gpu_wait build/test_omega_gpu_wait_om
	@./build/test_omega_gpu_wait >/dev/null || { echo "unflagged build FAILED"; exit 1; }
	@echo "unflagged: PASS"
	@set -e; for m in $(GPU_WAIT_MUTANTS); do \
	  gcc -std=gnu11 -O2 -Wall -Wextra -Werror -D_GNU_SOURCE -D$$m -Isrc -o build/test_omega_gpu_wait_$$m tests/test_omega_gpu_wait.c src/omega_gpu_wait.c; \
	  if ./build/test_omega_gpu_wait_$$m >build/test_omega_gpu_wait_$$m.log 2>&1; then echo "MUTANT SURVIVED: $$m"; exit 1; fi; \
	  echo "$$m: killed ($$(grep -c 'FAIL' build/test_omega_gpu_wait_$$m.log) failing checks)"; \
	done
	@./build/test_omega_gpu_wait_om >/dev/null || { echo "OM unedited build FAILED"; exit 1; }
	@echo "OM unedited: PASS"
	@set -e; for m in $(GPU_WAIT_MUTANTS); do \
	  sed "s/^const $$m int 0$$/const $$m int 1/" src/omega_gpu_wait.om > build/omega_gpu_wait_om_$$m.om; \
	  if cmp -s build/omega_gpu_wait_om_$$m.om src/omega_gpu_wait.om; then echo "MUTANT BROKEN: OM $$m edit changed nothing"; exit 1; fi; \
	  (printf 'om2\n'; sed '/^om2$$/d' build/omega_gpu_wait_om_$$m.om tests/test_omega_gpu_wait.om) | $(GPU_WAIT_OMC) > build/test_omega_gpu_wait_om_$$m; \
	  chmod +x build/test_omega_gpu_wait_om_$$m; \
	  if ./build/test_omega_gpu_wait_om_$$m >build/test_omega_gpu_wait_om_$$m.log 2>&1; then echo "MUTANT SURVIVED: OM $$m"; exit 1; fi; \
	  echo "OM $$m: killed ($$(grep -c 'FAIL' build/test_omega_gpu_wait_om_$$m.log) failing checks)"; \
	done
	@echo "OMEGA_GPU_WAIT_MUTANTS PASS"
