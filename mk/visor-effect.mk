# Omega Visor V1 lane 7 (effect requests) and lane 6 (World view): differential qualification of
# the OM-2 modules the omega binary runs (src/visor/visor_effect_request.om, visor_world.om)
# against the C they replace (src/visor/visor_effect_request.c, visor_world.c). Host only, CPU
# only, no physics checkout.
#
# test-visor-effect-parity
#   1. tests/visor/effect_parity.sh: the graph corpora (tests/visor/effect_corpus.txt and the
#      generated apply, relation, depth and padding corpora) through tests/visor/effect_dump.om,
#      byte for byte against the committed goldens of the C at main 3f2c70dc5
#      (tests/visor/effect_golden, MANIFEST with commit, generator and sha256): build rc,
#      classify rc and result, text and JSON renderings, object ids, the unattached World view;
#   2. tests/visor/effect_mutants.sh: every mutant of the OM lane must differ from the goldens;
#   3. tests/visor/check_world_unattached.sh on $(OMEGA_OM_SRCS): omega can only render the
#      unattached World view (the one the goldens pin), with three bite controls that must fail.
.PHONY: test-visor-effect-parity
test-visor-effect-parity: $(VISOR_OMC)
	EFFECT_PARITY_WORK=$(abspath $(OUT_DIR))/effect-parity sh tests/visor/effect_parity.sh $(abspath $(VISOR_OMC))
	EFFECT_PARITY_WORK=$(abspath $(OUT_DIR))/effect-parity sh tests/visor/effect_mutants.sh $(abspath $(VISOR_OMC))
	sh tests/visor/check_world_unattached.sh $(OMEGA_OM_SRCS)
	@d=$(abspath $(OUT_DIR))/world-bite; rm -rf $$d; mkdir -p $$d; n=0; \
	awk '{ print } /^fn vwld_format_text/ { print "  put vwld_attached 0 1" }' src/visor/visor_world.om > $$d/visor_world.om; \
	if sh tests/visor/check_world_unattached.sh $$d/visor_world.om tools/omega_ops.om > $$d/1.out; then echo "WORLD_UNATTACHED BITE FAIL: a view store outside the constructor passed"; exit 1; fi; n=$$((n + 1)); \
	awk '{ print } /^fn vom_world to long/ { print "  vwld_append_gap vwld_t_none" }' tools/omega_ops.om > $$d/omega_ops.om; \
	if sh tests/visor/check_world_unattached.sh src/visor/visor_world.om $$d/omega_ops.om > $$d/2.out; then echo "WORLD_UNATTACHED BITE FAIL: a gap append from omega passed"; exit 1; fi; n=$$((n + 1)); \
	grep -v '^  vwld_unattached$$' tools/omega_ops.om > $$d/omega_ops2.om; \
	if sh tests/visor/check_world_unattached.sh src/visor/visor_world.om $$d/omega_ops2.om > $$d/3.out; then echo "WORLD_UNATTACHED BITE FAIL: a rendering without vwld_unattached passed"; exit 1; fi; n=$$((n + 1)); \
	echo "WORLD_UNATTACHED bite controls: $$n/3 caught"
