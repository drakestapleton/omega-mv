# Native Omega Qwen 27B on AMD: final launcher qualification, 2026-11-13

This receipt exercises committed launcher source `ab58f17160bd9e9e29f9bc37c3668499bf752066` compiled
with the pinned Omega compiler `26540e6de62402d5784b30b24d7c6faae488137c1f8a4b3e784fd0b5d5528991`. The resulting x86 Linux
executable SHA256 is `08a504911ec6e87a9746632a14d22245155597e3a8ed384c93c0e5260bb691e1`. Production orchestration and all18
shader objects come from natural Omega. Python and C are independent test and
measurement instruments. This is a trusted first-party CLI dispatch-plan executor.
No HTTP service is claimed. Release approval and forge landing are separate.

The actual MI300X run passed both normal and nonzero-LDS vadd, original coding24
(all24 IDs, corrupted-weight control rejected by comparison), and a warmup plus
five lighthouse runs with30 prompt tokens,256 generated tokens and131072 capacity.
Every accepted lighthouse run matches all256 IDs of the independent AMD HIP graph.
That graph reference was reused from the earlier same-model/same18-objects run;
it is not a newly rerun HIP baseline. Model checkpoint verification covered68
files at the revision in host/qualification.json. Large weights and generated
plans are omitted; reproduction uses the emitter/checker in the preceding
`../amd-qwen38-native-20261113/oracle` receipt, and the scripts retained here.

Five decode medians are [26.731, 26.642, 26.675, 26.726, 26.76]. Their median is
**26.726 ms/token**, reciprocal **37.4167 tokens/s**.
The saved2026-11-01 Spark graph baseline is125.4 ms/token, a
**4.6921x** ratio of graph decode times. This is a
historical comparison, not a new simultaneous Spark measurement.
Median AMD prefill is **779.042 ms**, slower than the saved507 ms Spark
prefill. New-process AMD startup/first-ID timings and the warm HTTP Spark stream
boundary differ; they do not support a startup speed ratio. The sampled AMD
VRAM/GTT values and Spark unified RSS use different accounting.

This does not establish bitwise256-token Spark parity or model-quality equivalence.
The native AMD path first differs from Spark at generated index109 (zero-based),
matching the earlier independent AMD graph. The preceding receipt retains the
forced-prefix logits, including disagreements109 and138 at near ties; compare
those forced positions, not the diverged free-running suffix.

`native/environment.json` records live platform/topology. Raw stdout/stderr and
JSON are preserved. `native/DELIVERY_SHA256.json` is the original download inventory;
binary/object payloads are rebuilt from source rather than duplicated here.
`oracle/ORIGINAL_SCRIPTS.json` records exact pre-license-prefix script hashes.
`SHA256.json` covers every committed receipt file except itself. Run
`python3 -I evidence/amd-qwen38-native-refusal-20261113/verify.py` to verify inventory,
raw IDs/step order/timing calculations, control outcomes and coding24.
