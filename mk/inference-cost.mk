# Inference-cost benchmark: held-out evaluation of verified programs produced per unit of inference cost.
# Picked up by `-include mk/*.mk`.
ifndef INFERENCE_COST_MK
INFERENCE_COST_MK := 1
.PHONY: test-inference-cost test-handover

test-inference-cost:
	sh bench/inference_cost/driver.sh --self-test
	sh bench/inference_cost/tests/handover/run.sh

# The handover rule (bench/inference_cost/handover.om): known-verdict cases on TEST DATA and its mutants.
test-handover:
	sh bench/inference_cost/tests/handover/run.sh
endif
