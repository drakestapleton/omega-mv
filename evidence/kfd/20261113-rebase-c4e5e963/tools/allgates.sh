#!/bin/bash
# allgates.sh: every gate for the KFD rebase head, in order, each through gate.sh (pool lock, taskset, nice)
cd /home/drakestapleton/work/hive/amdserve/OmegaKfd/omega-mv || exit 2
G=/tmp/kfdrebase/gate.sh
git rev-parse HEAD > build/kfd-gates/head.txt
$G gate18 sh seed/omc/gate18.sh
$G semhash sh seed/semhash/check.sh
$G kfd-check python3 tests/kfd/check.py
$G seed bash tests/gates/run.sh seed
$G gate-pools sh seed/omc/gate-pools.sh
$G a64efi sh tests/a64efi/run.sh
$G x86efi sh tests/x86efi/run.sh
$G make-compiler make PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 test-compiler-quick test-numeric-cpu test-realize
$G evidence-immutable env AIEN_BASE_REF=c4e5e963d7f2e813ff88e61fe26c1f63d29ced22 bash tests/gates/run.sh evidence-immutable
$G zero-disk-secrets bash tests/gates/run.sh zero-disk-secrets
$G om-units bash tests/gates/run.sh om-units
$G irwasm bash tests/gates/run.sh irwasm
$G irspirv bash tests/gates/run.sh irspirv
$G orig4-shadow bash tests/gates/run.sh orig4-shadow
$G irequiv sh seed/equiv/gate-irequiv.sh
$G json sh seed/json/tests/gate-json.sh
$G irnki sh seed/nki/gate-irnki.sh
$G irstablehlo sh seed/stablehlo/gate-irstablehlo.sh
$G tensix sh seed/tensix/gate-tensix.sh
$G vkspirv sh seed/spirv/gate-vkspirv.sh
for u in aarch64 codec evidence gpumath receipt; do $G parity-$u sh om/$u/parity/run.sh; done
$G prefetch-native tools/run_gpu_l2d_prefetch_chip.sh --host-qualification
$G nl4 sh /tmp/kfdrebase/nl4.sh
git status --porcelain > build/kfd-gates/status-after.txt
echo ALLGATES-DONE
