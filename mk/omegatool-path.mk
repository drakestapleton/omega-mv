# omegatool must not embed the omega checkout or physics path (CAND-2 prep). The physics
# location is resolved at run time by src/omega_physics_dir.h (included by the C gate runners); the
# resolution rule and the pin checks run on that header and on its pure OM-2 port
# src/omega_physics_dir.om.
OMEGATOOL_PATH_OMC ?= seed/out/omc
OMEGATOOL_PATH_OM_SRCS := src/omega_physics_dir.om tests/omegatool_path/physics_dir_test.om
.PHONY: test-omegatool-path
$(OUT_DIR)/omegatool_path_test_om: $(OMEGATOOL_PATH_OM_SRCS) $(OMEGATOOL_PATH_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed '/^om2$$/d' $(OMEGATOOL_PATH_OM_SRCS)) | $(OMEGATOOL_PATH_OMC) > $@ && chmod +x $@
test-omegatool-path: $(OUT_DIR)/omegatool_path_test_om
	$(CC) -std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -O2 -Isrc -o $(OUT_DIR)/omegatool_path_test tests/omegatool_path/physics_dir_test.c
	$(OUT_DIR)/omegatool_path_test
	$(OUT_DIR)/omegatool_path_test_om
	PHYSICS_DIR=$(PHYSICS_DIR) tests/omegatool_path/no_embedded_path_test.sh
