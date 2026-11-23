# ANS, Inertial Alignment v1 (docs/ans/INERTIAL_ALIGNMENT_SPEC_V1.md, ARCH-0032).
# Pure seeded OM-2 standalone module under src/ans/ and tests/ans/.
# Picked up by `-include mk/*.mk`; not part of `all` or `test`. Nothing in
# src/runtime/ includes or links it. ANS is advisory: it never authorizes or promotes.
#
# test-ans                 unit suite (10 tests + 6 frozen SHA-256 goldens), built with seed/out/omc
# ans-purity               checks src/ans/*.om against forbidden runtime/authority/syscall/promote symbols
# test-inertial-alignment  both
ifndef ANS_MK
ANS_MK := 1
.PHONY: test-ans ans-purity test-inertial-alignment
ANS_DIR = $(OUT_DIR)/tests-ans
ANS_FORBIDDEN = 'rx_|aienos_|argus_|forge_|aegis|rx_gen_promote|\b(fopen|fclose|read|write|stat|renames|socknew|bind|listen|accept|send|recv|connect|execve|fork|mmap|malloc|calloc|realloc|free)\b'

ans-purity: src/ans/ans.om src/ans/ans_core.om
	@for f in src/ans/ans.om src/ans/ans_core.om; do \
		if sed -E '/^[[:space:]]*note([[:space:]].*)?$$/d' "$$f" | grep -nE $(ANS_FORBIDDEN) ; then \
			echo "ans module $$f references a forbidden runtime, authority, syscall or promotion symbol"; exit 1; fi; \
	done
	@echo "ans-purity: src/ans/ans.om and src/ans/ans_core.om reference no forbidden symbol and no rx_gen_promote"

$(ANS_DIR)/test_ans: src/ans/ans.om tests/ans/test_ans.om seed/out/omc
	@mkdir -p $(ANS_DIR)
	cat src/ans/ans.om tests/ans/test_ans.om | seed/out/omc > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

test-ans: $(ANS_DIR)/test_ans
	./$(ANS_DIR)/test_ans
	@echo "test-ans: ANS checks pass (pure seeded OM-2)"

test-inertial-alignment: ans-purity test-ans
	@echo "test-inertial-alignment: Inertial Alignment v1 (ANS) passes"
endif
