# GPU code buffer sizing (src/omega_gpu_code_alloc.om): the 2 KB instruction
# prefetch tail after every kernel (omega#323). Pure seeded OM-2, host only:
# no device, no physics headers. Runs the pure OM-2 size rule test, the NO_TAIL
# mutant, and the source scan refusing page-only code sizing idioms.
CODE_ALLOC_OMC ?= seed/out/omc
CODE_ALLOC_OM_SRCS := src/omega_gpu_code_alloc.om tests/test_omega_gpu_code_alloc.om
CODE_ALLOC_NO_TAIL_SED := s/^tail = OMEGA_GPU_CODE_PREFETCH_TAIL$$/tail = ulong 0/
CODE_ALLOC_SCAN_SRC := src/*.c src/runtime/*.c
CODE_ALLOC_SCAN_RE := code_size \+ 0x[fF]{3}|session_alloc\([^,]*code_size|alloc[a-z_]*\([^,]*, *(0x[0-9a-fA-F]+|OMEGA_DS_MAX_CODE_BYTES), *&[a-z_>.-]*code_mem\)
.PHONY: test-gpu-code-alloc
$(OUT_DIR)/test_omega_gpu_code_alloc_om: $(CODE_ALLOC_OM_SRCS) $(CODE_ALLOC_OMC)
	@mkdir -p $(OUT_DIR)
	(printf 'om2\n'; sed '/^om2$$/d' $(CODE_ALLOC_OM_SRCS)) | $(CODE_ALLOC_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
test-gpu-code-alloc: $(OUT_DIR)/test_omega_gpu_code_alloc_om
	./$(OUT_DIR)/test_omega_gpu_code_alloc_om
	@sed '$(CODE_ALLOC_NO_TAIL_SED)' src/omega_gpu_code_alloc.om > $(OUT_DIR)/omega_gpu_code_alloc_no_tail.om
	@if cmp -s $(OUT_DIR)/omega_gpu_code_alloc_no_tail.om src/omega_gpu_code_alloc.om; then echo "MUTANT BROKEN: OM NO_TAIL edit changed nothing"; exit 1; fi
	@(printf 'om2\n'; sed '/^om2$$/d' $(OUT_DIR)/omega_gpu_code_alloc_no_tail.om tests/test_omega_gpu_code_alloc.om) | $(CODE_ALLOC_OMC) > $(OUT_DIR)/test_omega_gpu_code_alloc_om_no_tail.tmp.$$$$ && chmod +x $(OUT_DIR)/test_omega_gpu_code_alloc_om_no_tail.tmp.$$$$ && mv -f $(OUT_DIR)/test_omega_gpu_code_alloc_om_no_tail.tmp.$$$$ $(OUT_DIR)/test_omega_gpu_code_alloc_om_no_tail
	@if ./$(OUT_DIR)/test_omega_gpu_code_alloc_om_no_tail >$(OUT_DIR)/test_omega_gpu_code_alloc_om_no_tail.log 2>&1; then echo "MUTANT SURVIVED: OM NO_TAIL"; exit 1; fi
	@echo "OM NO_TAIL mutant: killed ($$(grep -c '^FAIL:' $(OUT_DIR)/test_omega_gpu_code_alloc_om_no_tail.log) failing checks)"
	@if grep -nE '$(CODE_ALLOC_SCAN_RE)' $(CODE_ALLOC_SCAN_SRC); then echo "code buffer sized without the prefetch tail (use omega_gpu_code_alloc_bytes)"; exit 1; fi
	@echo "source scan: no page-only code sizing"
	@echo "OMEGA_GPU_CODE_ALLOC_GATE PASS"
