# GPU code buffer sizing (src/omega_gpu_code_alloc.h): the 2 KB instruction prefetch tail after every
# kernel (omega#323). Host only: no device, no physics headers. Parts: the size rule on the live C header
# that the GPU paths include, a NO_TAIL mutant of it that must fail; the same rule and mutant on the pure
# OM-2 port src/omega_gpu_code_alloc.om (the mutant is one edit of the .om); and a source scan that
# refuses the page-only code sizing idioms the six variable-size upload sites and five fixed-size sites
# used before.
CODE_ALLOC_OMC ?= seed/out/omc
CODE_ALLOC_OM_SRCS := src/omega_gpu_code_alloc.om tests/test_omega_gpu_code_alloc.om
CODE_ALLOC_NO_TAIL_SED := s/^tail = OMEGA_GPU_CODE_PREFETCH_TAIL$$/tail = ulong 0/
CODE_ALLOC_SCAN_SRC := src/*.c src/runtime/*.c
CODE_ALLOC_SCAN_RE := code_size \+ 0x[fF]{3}|session_alloc\([^,]*code_size|alloc[a-z_]*\([^,]*, *(0x[0-9a-fA-F]+|OMEGA_DS_MAX_CODE_BYTES), *&[a-z_>.-]*code_mem\)
.PHONY: test-gpu-code-alloc
build/test_omega_gpu_code_alloc: tests/test_omega_gpu_code_alloc.c src/omega_gpu_code_alloc.h
	@mkdir -p build
	gcc -std=gnu11 -O2 -Wall -Wextra -Werror -Isrc -o $@ tests/test_omega_gpu_code_alloc.c
build/test_omega_gpu_code_alloc_om: $(CODE_ALLOC_OM_SRCS) $(CODE_ALLOC_OMC)
	@mkdir -p build
	(printf 'om2\n'; sed '/^om2$$/d' $(CODE_ALLOC_OM_SRCS)) | $(CODE_ALLOC_OMC) > $@ && chmod +x $@
test-gpu-code-alloc: build/test_omega_gpu_code_alloc build/test_omega_gpu_code_alloc_om
	./build/test_omega_gpu_code_alloc
	@gcc -std=gnu11 -O2 -Wall -Wextra -Werror -DOMEGA_GPU_CODE_ALLOC_MUTANT_NO_TAIL -Isrc -o build/test_omega_gpu_code_alloc_no_tail tests/test_omega_gpu_code_alloc.c
	@if ./build/test_omega_gpu_code_alloc_no_tail >build/test_omega_gpu_code_alloc_no_tail.log 2>&1; then echo "MUTANT SURVIVED: NO_TAIL"; exit 1; fi
	@echo "NO_TAIL mutant: killed ($$(grep -c '^FAIL:' build/test_omega_gpu_code_alloc_no_tail.log) failing checks)"
	./build/test_omega_gpu_code_alloc_om
	@sed '$(CODE_ALLOC_NO_TAIL_SED)' src/omega_gpu_code_alloc.om > build/omega_gpu_code_alloc_no_tail.om
	@if cmp -s build/omega_gpu_code_alloc_no_tail.om src/omega_gpu_code_alloc.om; then echo "MUTANT BROKEN: OM NO_TAIL edit changed nothing"; exit 1; fi
	@(printf 'om2\n'; sed '/^om2$$/d' build/omega_gpu_code_alloc_no_tail.om tests/test_omega_gpu_code_alloc.om) | $(CODE_ALLOC_OMC) > build/test_omega_gpu_code_alloc_om_no_tail && chmod +x build/test_omega_gpu_code_alloc_om_no_tail
	@if ./build/test_omega_gpu_code_alloc_om_no_tail >build/test_omega_gpu_code_alloc_om_no_tail.log 2>&1; then echo "MUTANT SURVIVED: OM NO_TAIL"; exit 1; fi
	@echo "OM NO_TAIL mutant: killed ($$(grep -c '^FAIL:' build/test_omega_gpu_code_alloc_om_no_tail.log) failing checks)"
	@if grep -nE '$(CODE_ALLOC_SCAN_RE)' $(CODE_ALLOC_SCAN_SRC); then echo "code buffer sized without the prefetch tail (use omega_gpu_code_alloc_bytes)"; exit 1; fi
	@echo "source scan: no page-only code sizing"
	@echo "OMEGA_GPU_CODE_ALLOC_GATE PASS"
