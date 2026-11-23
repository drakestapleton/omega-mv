# omegatool must not embed the omega checkout or physics path (CAND-2 prep). The physics
# location is resolved at run time by src/omega_physics_dir.h; the resolution rule and the pin
# checks are tested on its pure OM-2 port src/omega_physics_dir.om.
OMEGATOOL_PATH_OMC ?= seed/out/omc
OMEGATOOL_PATH_OM_SRCS := src/omega_physics_dir.om tests/omegatool_path/physics_dir_test.om
.PHONY: test-omegatool-path
$(OUT_DIR)/omegatool_path_test: $(OMEGATOOL_PATH_OM_SRCS) $(OMEGATOOL_PATH_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(OMEGATOOL_PATH_OM_SRCS)) | $(OMEGATOOL_PATH_OMC) > $@ && chmod +x $@
test-omegatool-path: $(OUT_DIR)/omegatool_path_test
	$(OUT_DIR)/omegatool_path_test
	PHYSICS_DIR=$(PHYSICS_DIR) tests/omegatool_path/no_embedded_path_test.sh
