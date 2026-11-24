# Omega Visor V1, lane 6 (World view). Pure seeded OM-2, host-only, physics-free.
VISOR_WORLD_OMC ?= seed/out/omc
VISOR_WORLD_OM_SRCS := src/visor/visor.om src/visor/visor_world.om tests/visor/test_visor_world.om
VISOR_WORLD_TEST = $(OUT_DIR)/tests-visor-world/test_visor_world

$(OUT_DIR)/tests-visor-world:
	mkdir -p $@

$(VISOR_WORLD_TEST): $(VISOR_WORLD_OM_SRCS) $(VISOR_WORLD_OMC) | $(OUT_DIR)/tests-visor-world
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(VISOR_WORLD_OM_SRCS)) | $(VISOR_WORLD_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-visor-world
test-visor-world: $(VISOR_WORLD_TEST)
	$(abspath $(VISOR_WORLD_TEST))
