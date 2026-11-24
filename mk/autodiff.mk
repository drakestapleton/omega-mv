# M21 OMEGA_AUTODIFF (docs/autodiff/M21_OMEGA_AUTODIFF.md): reverse-mode tape
# over the M20 tensor CPU tier. Pure seeded OM-2 under src/autodiff/.
# Picked up by `-include mk/*.mk`. Not part of `all` or `test`. CPU only:
# opens no device, never touches the GB10.
#
# test-autodiff            pure OM-2 CPU tests (src/autodiff/test_autodiff.om)
# test-autodiff-mutations  applies each MUT: source mutation of src/autodiff
#                          in a scratch copy and proves the test then fails
# autodiff-mutants         alias of test-autodiff-mutations
# test-autodiff-fixture    FIXTURE=<path>: replays a native .om tape fixture
#                          (native/autodiff664) on the pure OM-2 M21 tape,
#                          CPU table; the --mutant-sign negative control must
#                          FAIL. The GB10 arm is tests/run_ad_chip.sh, not here.
ifndef AUTODIFF_MK
AUTODIFF_MK := 1
.PHONY: test-autodiff test-autodiff-mutations autodiff-mutants test-autodiff-fixture

AUTODIFF_OMC ?= seed/out/omc
AUTODIFF_OM_SRCS = src/tensor/tensor_shape.om src/tensor/tensor_ops.om src/train/tg_sha256.om \
	src/tensor/omega_tensor_cpu.om src/tensor/omega_tensor.om \
	src/autodiff/gradient_shape.om src/autodiff/omega_autodiff.om

$(OUT_DIR)/test_omega_autodiff: src/autodiff/test_autodiff.om $(AUTODIFF_OM_SRCS) $(AUTODIFF_OMC)
	@mkdir -p $(OUT_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(AUTODIFF_OM_SRCS) src/autodiff/test_autodiff.om) | $(AUTODIFF_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

test-autodiff: $(OUT_DIR)/test_omega_autodiff
	$(abspath $(OUT_DIR)/test_omega_autodiff)

$(OUT_DIR)/test_omega_ad_fixture: src/autodiff/test_ad_fixture.om $(AUTODIFF_OM_SRCS) $(AUTODIFF_OMC)
	@mkdir -p $(OUT_DIR)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(AUTODIFF_OM_SRCS) src/autodiff/test_ad_fixture.om) | $(AUTODIFF_OMC) > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

test-autodiff-fixture: $(OUT_DIR)/test_omega_ad_fixture
	@test -n "$(FIXTURE)" || { echo "test-autodiff-fixture needs FIXTURE=<path>"; exit 2; }
	$(abspath $(OUT_DIR)/test_omega_ad_fixture) --host $(FIXTURE)
	@$(abspath $(OUT_DIR)/test_omega_ad_fixture) --host --mutant-sign $(FIXTURE); rc=$$?; \
	 if [ $$rc -ne 1 ]; then echo "mutant-sign control did not FAIL (rc=$$rc)"; exit 1; fi; \
	 echo "AD_FIXTURE_HOST mutant-sign control: FAIL as required"

test-autodiff-mutations:
	sh tools/autodiff_mutations.sh

autodiff-mutants: test-autodiff-mutations
endif
