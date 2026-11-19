# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# External calculation and evidence verifier, not a production dependency.
from pathlib import Path
import json,statistics
D=Path(__file__).resolve().parent
v=json.loads((D/'native/state.json').read_text())
a=[r for r in v['rows'] if r['label']!='warmup']
assert v['phase']=='complete' and len(a)==5
assert all(r['shape_ok'] and r['hip_ids_equal'] and r['steps']==285 for r in a)
assert v['control']['shape_ok'] and not v['control']['hip_ids_equal']
assert all(r['ids']==json.loads((D/'numerical/graph.json').read_text())['ids'] for r in a)
ms=statistics.median(r['decode_ms_median'] for r in a)
b=json.loads((D/'spark-baseline/qualification.json').read_text())
r=dict(accepted_decode_ms=[r['decode_ms_median'] for r in a],median_decode_ms=ms,
 derived_reciprocal_median_step_tokens_s=1000/ms,historical_spark_graph_ms=b['graph_ms_per_token'],
 historical_spark_graph_time_ratio=b['graph_ms_per_token']/ms,
 median_prefill_ms=statistics.median(r['prefill_ms'] for r in a),
 median_process_ready_s=statistics.median(r['marks']['ready_s'] for r in a),
 median_process_first_generated_id_s=statistics.median(r['marks']['first_generated_id_s'] for r in a),
 median_process_total_s=statistics.median(r['total_s'] for r in a),
 sampled_peak_rss_kib=max(r['memory_peak']['rss_kib'] for r in a),
 sampled_peak_vram_kib=max(r['memory_peak']['drm']['drm-memory-vram']['value'] for r in a),
 sampled_peak_gtt_kib=max(r['memory_peak']['drm']['drm-memory-gtt']['value'] for r in a))
print(json.dumps(r,indent=2))
