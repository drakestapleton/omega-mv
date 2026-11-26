# omegatool must not embed the omega checkout or physics path (CAND-2 prep). The physics
# location is resolved at run time by src/omega_physics_dir.om; the resolution rule,
# pin checks, and zero-embedded-path check run in pure seeded OM-2.
OMEGATOOL_PATH_OMC ?= seed/out/omc
OMEGATOOL_PATH_OM_SRCS := src/omega_physics_dir.om tests/omegatool_path/physics_dir_test.om
.PHONY: test-omegatool-path
$(OUT_DIR)/omegatool_path_test_om: $(OMEGATOOL_PATH_OM_SRCS) $(OMEGATOOL_PATH_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(OMEGATOOL_PATH_OM_SRCS)) | $(OMEGATOOL_PATH_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@
test-omegatool-path: $(OUT_DIR)/omegatool_path_test_om
	$(OUT_DIR)/omegatool_path_test_om
	PHYSICS_DIR=$(PHYSICS_DIR) tests/omegatool_path/no_embedded_path_test.sh
