# Shared GPU completion wait primitive (src/omega_gpu_wait.om): pure seeded OM-2
# host unit test with fake memory and fake clock, plus all three load-bearing
# mutants. Host only: opens no device, needs no physics headers, takes no chip lock.
GPU_WAIT_OMC ?= seed/out/omc
GPU_WAIT_OM_SRCS := src/omega_gpu_wait.om tests/test_omega_gpu_wait.om
.PHONY: test-gpu-wait
$(OUT_DIR)/test_omega_gpu_wait_om: $(GPU_WAIT_OM_SRCS) $(GPU_WAIT_OMC)
	@mkdir -p $(OUT_DIR)
	(printf 'om2\n'; sed '/^om2$$/d' $(GPU_WAIT_OM_SRCS)) | $(GPU_WAIT_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
test-gpu-wait: $(OUT_DIR)/test_omega_gpu_wait_om
	./$(OUT_DIR)/test_omega_gpu_wait_om

# Real-code mutants: src/omega_gpu_wait.om carries three one-line mutant constants.
# Each copy with one constant set to 1 must FAIL the suite; the unedited build must PASS.
GPU_WAIT_MUTANTS := OMEGA_GPU_WAIT_MUTANT_STALL_NO_RESET OMEGA_GPU_WAIT_MUTANT_PROGRESS_EXTENDS_HARD OMEGA_GPU_WAIT_MUTANT_NO_READ_BARRIER
.PHONY: test-gpu-wait-mutants
test-gpu-wait-mutants: $(OUT_DIR)/test_omega_gpu_wait_om
	@./$(OUT_DIR)/test_omega_gpu_wait_om >/dev/null || { echo "OM unedited build FAILED"; exit 1; }
	@echo "OM unedited: PASS"
	@set -e; for m in $(GPU_WAIT_MUTANTS); do \
	  sed "s/^const $$m int 0$$/const $$m int 1/" src/omega_gpu_wait.om > $(OUT_DIR)/omega_gpu_wait_om_$$m.om; \
	  if cmp -s $(OUT_DIR)/omega_gpu_wait_om_$$m.om src/omega_gpu_wait.om; then echo "MUTANT BROKEN: OM $$m edit changed nothing"; exit 1; fi; \
	  (printf 'om2\n'; sed '/^om2$$/d' $(OUT_DIR)/omega_gpu_wait_om_$$m.om tests/test_omega_gpu_wait.om) | $(GPU_WAIT_OMC) > $(OUT_DIR)/test_omega_gpu_wait_om_$$m.tmp.$$$$; \
	  chmod +x $(OUT_DIR)/test_omega_gpu_wait_om_$$m.tmp.$$$$; \
	  mv -f $(OUT_DIR)/test_omega_gpu_wait_om_$$m.tmp.$$$$ $(OUT_DIR)/test_omega_gpu_wait_om_$$m; \
	  if ./$(OUT_DIR)/test_omega_gpu_wait_om_$$m >$(OUT_DIR)/test_omega_gpu_wait_om_$$m.log 2>&1; then echo "MUTANT SURVIVED: OM $$m"; exit 1; fi; \
	  echo "OM $$m: killed ($$(grep -c 'FAIL' $(OUT_DIR)/test_omega_gpu_wait_om_$$m.log) failing checks)"; \
	done
	@echo "OMEGA_GPU_WAIT_MUTANTS PASS"
