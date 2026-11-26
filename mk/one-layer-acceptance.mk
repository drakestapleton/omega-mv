# One-layer stage 1: hostile acceptance harness (omega#443, tests/one_layer/acceptance/).
# Legacy OSC-1 C runner (ola.c, ola_runner.c, mkoscir.c) depended on removed src/compiler/ (bb7f2dd68)
# and is retired; pure seeded OM-2 sample IR encoder runs via test-one-layer-mkopir-om.
ifndef ONE_LAYER_ACCEPTANCE_MK
ONE_LAYER_ACCEPTANCE_MK := 1
.PHONY: one-layer-acceptance-tools test-one-layer-acceptance

one-layer-acceptance-tools test-one-layer-acceptance:
	@echo "MISSING_IMPLEMENTATION: $@ requires removed legacy src/compiler/ (oscc/osc_front.h, removed in bb7f2dd68); run test-one-layer-mkopir-om for pure OM-2 IR verification" >&2
	@exit 3
endif
