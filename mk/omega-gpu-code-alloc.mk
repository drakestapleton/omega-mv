# GPU code buffer sizing: the 2 KB instruction prefetch tail after every kernel (omega#323). The C GPU
# paths include src/omega_gpu_code_alloc.h; the size rule is tested on its pure OM-2 port
# src/omega_gpu_code_alloc.om (same rule, same output as the former C test). Host only: no device, no
# physics headers. Three parts: the size rule, a NO_TAIL mutant (one edit of the .om, the page-rounded
# size used before omega#323) that must fail it, and a source scan that refuses the page-only code
# sizing idioms the six variable-size upload sites and five fixed-size sites used before.
CODE_ALLOC_OMC ?= seed/out/omc
CODE_ALLOC_OM_SRCS := src/omega_gpu_code_alloc.om tests/test_omega_gpu_code_alloc.om
CODE_ALLOC_NO_TAIL_SED := s/^tail = OMEGA_GPU_CODE_PREFETCH_TAIL$$/tail = ulong 0/
CODE_ALLOC_SCAN_SRC := src/*.c src/runtime/*.c
CODE_ALLOC_SCAN_RE := code_size \+ 0x[fF]{3}|session_alloc\([^,]*code_size|alloc[a-z_]*\([^,]*, *(0x[0-9a-fA-F]+|OMEGA_DS_MAX_CODE_BYTES), *&[a-z_>.-]*code_mem\)
.PHONY: test-gpu-code-alloc
build/test_omega_gpu_code_alloc: $(CODE_ALLOC_OM_SRCS) $(CODE_ALLOC_OMC)
	@mkdir -p build
	(printf 'om2\n'; sed '/^om2$$/d' $(CODE_ALLOC_OM_SRCS)) | $(CODE_ALLOC_OMC) > $@ && chmod +x $@
test-gpu-code-alloc: build/test_omega_gpu_code_alloc
	./build/test_omega_gpu_code_alloc
	@sed '$(CODE_ALLOC_NO_TAIL_SED)' src/omega_gpu_code_alloc.om > build/omega_gpu_code_alloc_no_tail.om
	@if cmp -s build/omega_gpu_code_alloc_no_tail.om src/omega_gpu_code_alloc.om; then echo "MUTANT BROKEN: NO_TAIL edit changed nothing"; exit 1; fi
	@(printf 'om2\n'; sed '/^om2$$/d' build/omega_gpu_code_alloc_no_tail.om tests/test_omega_gpu_code_alloc.om) | $(CODE_ALLOC_OMC) > build/test_omega_gpu_code_alloc_no_tail && chmod +x build/test_omega_gpu_code_alloc_no_tail
	@if ./build/test_omega_gpu_code_alloc_no_tail >build/test_omega_gpu_code_alloc_no_tail.log 2>&1; then echo "MUTANT SURVIVED: NO_TAIL"; exit 1; fi
	@echo "NO_TAIL mutant: killed ($$(grep -c '^FAIL:' build/test_omega_gpu_code_alloc_no_tail.log) failing checks)"
	@if grep -nE '$(CODE_ALLOC_SCAN_RE)' $(CODE_ALLOC_SCAN_SRC); then echo "code buffer sized without the prefetch tail (use omega_gpu_code_alloc_bytes)"; exit 1; fi
	@echo "source scan: no page-only code sizing"
	@echo "OMEGA_GPU_CODE_ALLOC_GATE PASS"
