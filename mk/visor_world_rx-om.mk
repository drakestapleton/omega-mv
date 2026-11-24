# Visor World RxWorld snapshot (src/visor/rx/visor_world_rx.om, twin of src/visor/rx/visor_world_rx.c).
# Pure seeded OM-2, physics-free, host-only.
VISOR_WORLD_RX_OM_OMC ?= seed/out/omc
VISOR_WORLD_RX_OM_SRCS := src/visor/visor.om src/visor/visor_world.om src/visor/rx/visor_world_rx.om tests/visor/test_visor_world_rx.om
VISOR_WORLD_RX_OM_TEST = $(OUT_DIR)/test_visor_world_rx_om

$(VISOR_WORLD_RX_OM_TEST): $(VISOR_WORLD_RX_OM_SRCS) $(VISOR_WORLD_RX_OM_OMC)
	@mkdir -p $(dir $@)
	(printf 'om2\n'; sed -e '/^om2$$/d' -e 's/^export fn /fn /' $(VISOR_WORLD_RX_OM_SRCS)) | $(VISOR_WORLD_RX_OM_OMC) > $@.tmp.$$$$ && chmod +x $@.tmp.$$$$ && mv -f $@.tmp.$$$$ $@

.PHONY: test-visor-world-rx-om
test-visor-world-rx-om: $(VISOR_WORLD_RX_OM_TEST)
	$(abspath $(VISOR_WORLD_RX_OM_TEST))
