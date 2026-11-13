#!/bin/bash
# External acceptance instrument; invoked under a CPU pool lock and nice.
set -u
B=build/kfd-r3
step() { n=$1; shift; start=$(date -u +%FT%TZ); "$@" > "$B/logs/$n.log" 2>&1; r=$?; printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$r" "$start" "$(date -u +%FT%TZ)" "$*" >> "$B/exits.tsv"; echo "$n exit=$r"; }
step gate18 sh seed/omc/gate18.sh
step semhash sh seed/semhash/check.sh
step kfd-check python3 tests/kfd/check.py
step seed bash tests/gates/run.sh seed
step gate-pools sh seed/omc/gate-pools.sh
step a64efi env TMPDIR=/tmp sh tests/a64efi/run.sh
step x86efi env TMPDIR=/tmp sh tests/x86efi/run.sh
step make-compiler make PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 test-compiler-quick test-numeric-cpu test-realize
step evidence-immutable env AIEN_BASE_REF=ace2691c396d3fbb4d0368170ca85b3fa5ab2e7d bash tests/gates/run.sh evidence-immutable
step zero-disk-secrets bash tests/gates/run.sh zero-disk-secrets
step om-units bash tests/gates/run.sh om-units
step irwasm bash tests/gates/run.sh irwasm
step orig4-shadow bash tests/gates/run.sh orig4-shadow
step irequiv sh seed/equiv/gate-irequiv.sh
step json sh seed/json/tests/gate-json.sh
step parity-codec sh om/codec/parity/run.sh --mutants
for u in aarch64 evidence gpumath receipt; do step parity-$u env OMEGA_OMC="$PWD/seed/out/omc" OMEGA_BRIDGE="$PWD/build/pins/omega-bridge-94a83e8" sh om/$u/parity/run.sh; done
step prefetch-native tools/run_gpu_l2d_prefetch_chip.sh --host-qualification
step nl4 sh evidence/kfd/20261113-rebase-c4e5e963/tools/nl4.sh
source "$HOME/work/E1Open/tools/env.sh"
step irspirv bash tests/gates/run.sh irspirv
step irnki env NKI_ORACLE_DIR="$PWD/../oracles/nki" sh seed/nki/gate-irnki.sh
step irstablehlo env IREE_COMPILE="$PWD/../oracles/iree/bin/iree-compile" IREE_RUN="$PWD/../oracles/iree/bin/iree-run-module" PYTHON="$PWD/../oracles/iree/bin/python" sh seed/stablehlo/gate-irstablehlo.sh
step tensix sh seed/tensix/gate-tensix.sh
step vkspirv env PORTLAB_DIR="$HOME/handoffs/PortLab/work/omega-mv/bench/portlab" VULKAN_CFLAGS="-I$PWD/../oracles/vk/root/usr/include" VULKAN_LIBS=/usr/lib/aarch64-linux-gnu/libvulkan.so.1 sh seed/spirv/gate-vkspirv.sh
step neg-head bash -c 'seed/out/omc < build/kfd-r3/neg2.om > build/kfd-r3/neg.head.bin'
step neg-main bash -c 'build/kfd-r3/omc-main < build/kfd-r3/neg2.om > build/kfd-r3/neg.main.bin'
echo DONE
