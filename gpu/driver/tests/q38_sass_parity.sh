#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Pure seeded-Omega Qwen3.8-27B sm_121 differential SASS + MONK parity gate:
#   - Compiles every pure-OM tool 2x deterministically (zero C/gcc invocation)
#   - Verifies cg_dec + bw_alloc + gpu/nvidia/om/encoder/bw_enc_sm121.om
#     bit-identical across all 7 kernels against canonical om/encoder/bw_enc_sm121.om
#   - Verifies all 7 kernels structurally via seed/helix/monk_check.om (HXP1 cert -> exit 0)
#   - Verifies 2 genuine monk_check negative controls (digest tamper -> exit 12,
#     stall shave on k0 insn 12 -> exit 17)
# Runs on both DGX Spark (Linux AArch64 ELF) and MacBook (Darwin target a64macos).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
OS=$(uname -s)

if [ -n "${OMC:-}" ]; then
    OMC_BIN="$OMC"
elif [ "$OS" = "Darwin" ] && [ -x "${HOME:-}/.local/bin/omc" ]; then
    OMC_BIN="${HOME}/.local/bin/omc"
elif [ "$OS" = "Darwin" ] && command -v omc >/dev/null 2>&1; then
    OMC_BIN=$(command -v omc)
else
    OMC_BIN="$ROOT/seed/out/omc"
fi

[ -x "$OMC_BIN" ] || { echo "FAIL q38_sass_parity: missing omc at $OMC_BIN" >&2; exit 2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/q38_sass_parity.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

TGT_HDR=""
if [ "$OS" = "Darwin" ]; then
    TGT_HDR="target a64macos
"
fi

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

sign_bin() {
    if [ "$OS" = "Darwin" ]; then
        codesign --force --sign - "$1" >/dev/null 2>&1 || true
    fi
}

compile_2x() {
    local name="$1"
    local src="$2"
    "$OMC_BIN" < "$src" > "$TMP/${name}.1"
    "$OMC_BIN" < "$src" > "$TMP/${name}.2"
    cmp -s "$TMP/${name}.1" "$TMP/${name}.2" || {
        echo "FAIL q38_sass_parity: non-deterministic omc build for $name" >&2
        exit 1
    }
    chmod 700 "$TMP/${name}.1"
    mv -f "$TMP/${name}.1" "$TMP/$name"
    rm -f "$TMP/${name}.2"
    sign_bin "$TMP/$name"
    echo "  2x-det $name: PASS (sha256=$(hash_file "$TMP/$name"))"
}

cat > "$TMP/q38_hxp1_src.om" <<'EOF'
text h_m_use "usage: q38_hxp1 TMP_DIR\n"
text h_m_sz "FAIL q38_hxp1: framed SASS size mismatch\n"
text h_m_cnt "FAIL q38_hxp1: expected 7 kernels\n"
text h_m_par "FAIL q38_hxp1: bw_enc_sm121 byte mismatch\n"
text h_m_io "FAIL q38_hxp1: file I/O error\n"
text h_s_ref "/enc_gpu.sass"
text h_s_can "/enc_canon.sass"
text h_s_k "/k"
text h_s_r ".ref.bin"
text h_s_c ".cand.bin"
text h_s_h ".hxp1"
text h_s_tamp "/k0.tamper.bin"
text h_s_shv "/k0.shave.bin"
text h_s_shvc "/k0.shave.hxp1"
text h_m_ok "  hxp1_unpack: 7/7 kernels unframed + canonical-encoder bit-exact (bytes="
text h_m_ok2 ")\n"

global g_dir uchar 512
global g_path uchar 1024
global g_ref uchar 65536
global g_can uchar 65536
global g_cert uchar 8300
global g_k0 uchar 32768
global g_k0_len ulong 1
global g_dig_ref uchar 32

fn wr_err msg view uchar * to void
  r = write 2 msg 0 len msg
end

fn wr_out msg view uchar * to void
  r = write 1 msg 0 len msg
end

fn wr_u64 v ulong to void
  b = new uchar 24 0
  p = ulong 24
  n = v
  while true
    p = sub p 1
    put b p uchar add 48 rem n 10
    n = div n 10
    if eq n 0
      ign = write 1 b p sub 24 p
      ret
    end
  end
end

fn mk_path dlen ulong sfx view uchar * to ulong
  p = ulong 0
  for i ulong dlen bound 512
    put g_path p get g_dir i
    p = add p 1
  end
  for i ulong len sfx bound 256
    put g_path p get sfx i
    p = add p 1
  end
  put g_path p uchar 0
  ret p
end

fn mk_kpath dlen ulong k ulong sfx view uchar * to ulong
  p = ulong 0
  for i ulong dlen bound 512
    put g_path p get g_dir i
    p = add p 1
  end
  for i ulong len h_s_k bound 16
    put g_path p get h_s_k i
    p = add p 1
  end
  put g_path p uchar add 48 k
  p = add p 1
  for i ulong len sfx bound 64
    put g_path p get sfx i
    p = add p 1
  end
  put g_path p uchar 0
  ret p
end

fn rd_whole plen ulong is_can bool to long
  fd = fopen g_path 0 plen 0 0
  if lt fd 0
    ret -1
  end
  tot = ulong 0
  while lt tot 65536 bound 512
    r = long 0
    if is_can
      r = read int fd g_can tot sub 65536 tot
    else
      r = read int fd g_ref tot sub 65536 tot
    end
    if le r 0
      break
    end
    tot = add tot ulong r
  end
  z = fclose int fd
  ret long tot
end

fn wr_file plen ulong is_cert bool n ulong to bool
  fd = fopen g_path 0 plen 577 420
  if lt fd 0
    ret false
  end
  off = ulong 0
  while lt off n bound 4096
    w = long 0
    if is_cert
      w = write int fd g_cert off sub n off
    else
      w = write int fd sh_dat off sub n off
    end
    if le w 0
      z = fclose int fd
      ret false
    end
    off = add off ulong w
  end
  z = fclose int fd
  ret true
end

fn rd_u32_ref off ulong to ulong
  v = ulong get g_ref off
  v = or v shl ulong get g_ref add off 1 8
  v = or v shl ulong get g_ref add off 2 16
  v = or v shl ulong get g_ref add off 3 24
  ret v
end

fn put_u32_cert off ulong v ulong to void
  put g_cert off uchar and v 255
  put g_cert add off 1 uchar and shr v 8 255
  put g_cert add off 2 uchar and shr v 16 255
  put g_cert add off 3 uchar and shr v 24 255
end

fn fill_hxp1 nins ulong use_saved_ref bool to ulong
  put g_cert 0 uchar 72
  put g_cert 1 uchar 88
  put g_cert 2 uchar 80
  put g_cert 3 uchar 49
  put_u32_cert 4 nins
  for i ulong 32
    if use_saved_ref
      put g_cert add 8 i get g_dig_ref i
    else
      put g_cert add 8 i get sh_dig i
    end
    put g_cert add 40 i get sh_dig i
  end
  for j ulong nins bound 2048
    put_u32_cert add 72 mul j 4 j
  end
  ret add 72 mul nins 4
end

fn emit_one_kernel dlen ulong k ulong off ulong nb ulong to int
  nins = div nb 16
  for i ulong nb bound 32768
    b = get g_ref add off i
    put sh_dat i b
    if eq k 0
      put g_k0 i b
    end
  end
  sh_all nb
  if eq k 0
    put g_k0_len 0 nb
    for i ulong 32
      put g_dig_ref i get sh_dig i
    end
  end
  clen = fill_hxp1 nins false
  p1 = mk_kpath dlen k h_s_r
  if not wr_file p1 false nb
    wr_err h_m_io
    ret 2
  end
  p2 = mk_kpath dlen k h_s_c
  if not wr_file p2 false nb
    wr_err h_m_io
    ret 2
  end
  p3 = mk_kpath dlen k h_s_h
  if not wr_file p3 true clen
    wr_err h_m_io
    ret 2
  end
  ret 0
end

fn emit_negative_controls dlen ulong to int
  k0_len = get g_k0_len 0
  for i ulong k0_len bound 32768
    put sh_dat i get g_k0 i
  end
  put sh_dat 0 xor get sh_dat 0 uchar 1
  pt = mk_path dlen h_s_tamp
  if not wr_file pt false k0_len
    wr_err h_m_io
    ret 2
  end

  for i ulong k0_len bound 32768
    put sh_dat i get g_k0 i
  end
  note Shave w3[12:9] stall on k0 insn 12 (byte 12*16+13 = 205) to stall=1
  idx_b = ulong 205
  put sh_dat idx_b or and get sh_dat idx_b uchar 0xe1 uchar 0x02
  sh_all k0_len
  clen = fill_hxp1 div k0_len 16 true
  ps = mk_path dlen h_s_shv
  if not wr_file ps false k0_len
    wr_err h_m_io
    ret 2
  end
  psc = mk_path dlen h_s_shvc
  if not wr_file psc true clen
    wr_err h_m_io
    ret 2
  end
  ret 0
end

fn unpack_all dlen ulong tot ulong to int
  off = ulong 0
  k = ulong 0
  while lt off tot bound 64
    if gt add off 4 tot
      wr_err h_m_sz
      ret 1
    end
    nb = rd_u32_ref off
    off = add off 4
    if eq nb 0
      wr_err h_m_sz
      ret 1
    end
    if gt nb 32768
      wr_err h_m_sz
      ret 1
    end
    if ne rem nb 16 0
      wr_err h_m_sz
      ret 1
    end
    if gt add off nb tot
      wr_err h_m_sz
      ret 1
    end
    rc = emit_one_kernel dlen k off nb
    if ne rc 0
      ret rc
    end
    off = add off nb
    k = add k 1
  end
  if ne k 7
    wr_err h_m_cnt
    ret 1
  end
  ret 0
end

fn main to int
  if ne argcnt 2
    wr_err h_m_use
    ret 2
  end
  dl = argread 1 g_dir 0 500
  if le dl 0
    wr_err h_m_use
    ret 2
  end
  dlen = ulong dl

  nref = rd_whole mk_path dlen h_s_ref false
  ncan = rd_whole mk_path dlen h_s_can true
  if or lt nref 0 lt ncan 0
    wr_err h_m_io
    ret 2
  end
  if or ne nref ncan eq nref 0
    wr_err h_m_sz
    ret 1
  end
  tot = ulong nref
  for i ulong tot bound 65536
    if ne get g_ref i get g_can i
      wr_err h_m_par
      ret 1
    end
  end

  rc1 = unpack_all dlen tot
  if ne rc1 0
    ret rc1
  end
  rc2 = emit_negative_controls dlen
  if ne rc2 0
    ret rc2
  end

  wr_out h_m_ok
  wr_u64 tot
  wr_out h_m_ok2
  ret 0
end
EOF

printf '%s' "$TGT_HDR" > "$TMP/om_emit.om"
cat "$ROOT/gpu/nvidia/om/codegen/cg_dec_emit.om" \
    "$ROOT/gpu/nvidia/om/codegen/cg_dec.om" \
    "$ROOT/gpu/driver/tests/q38_sass_emit.om" >> "$TMP/om_emit.om"

printf '%s' "$TGT_HDR" > "$TMP/om_enc.om"
cat "$ROOT/gpu/nvidia/om/components/bw_alloc.om" \
    "$ROOT/gpu/nvidia/om/encoder/bw_enc_sm121.om" \
    "$ROOT/gpu/driver/tests/q38_sass_encode.om" >> "$TMP/om_enc.om"

printf '%s' "$TGT_HDR" > "$TMP/om_enc_canon.om"
cat "$ROOT/gpu/nvidia/om/components/bw_alloc.om" \
    "$ROOT/om/encoder/bw_enc_sm121.om" \
    "$ROOT/gpu/driver/tests/q38_sass_encode.om" >> "$TMP/om_enc_canon.om"

printf '%som2\n' "$TGT_HDR" > "$TMP/monk_check.om"
sed -e '/^om2$/d' \
    "$ROOT/seed/ng/sha256.om" \
    "$ROOT/gpu/nvidia/om/codegen/bw_hazard.om" \
    "$ROOT/seed/helix/hx_dec_ext.om" \
    "$ROOT/seed/helix/monk_check.om" >> "$TMP/monk_check.om"

printf '%som2\n' "$TGT_HDR" > "$TMP/q38_hxp1.om"
sed -e '/^om2$/d' "$ROOT/seed/ng/sha256.om" "$TMP/q38_hxp1_src.om" >> "$TMP/q38_hxp1.om"

compile_2x om_emit "$TMP/om_emit.om"
compile_2x om_enc "$TMP/om_enc.om"
compile_2x om_enc_canon "$TMP/om_enc_canon.om"
compile_2x monk_check "$TMP/monk_check.om"
compile_2x q38_hxp1 "$TMP/q38_hxp1.om"

"$TMP/om_emit" > "$TMP/emitted.bin"
"$TMP/om_enc" < "$TMP/emitted.bin" > "$TMP/enc_gpu.sass"
"$TMP/om_enc_canon" < "$TMP/emitted.bin" > "$TMP/enc_canon.sass"

cmp -s "$TMP/enc_gpu.sass" "$TMP/enc_canon.sass" || {
    echo "FAIL q38_sass_parity: gpu/nvidia/om/encoder/bw_enc_sm121.om != om/encoder/bw_enc_sm121.om" >&2
    exit 1
}

"$TMP/q38_hxp1" "$TMP"

k=0
while [ "$k" -lt 7 ]; do
    mout=$("$TMP/monk_check" "$TMP/k${k}.ref.bin" "$TMP/k${k}.cand.bin" "$TMP/k${k}.hxp1") || {
        echo "FAIL q38_sass_parity: monk_check rejected kernel $k: $mout" >&2
        exit 1
    }
    echo "  k${k}: $mout"
    k=$((k + 1))
done

rc_tamp=0
tamp_out=$("$TMP/monk_check" "$TMP/k0.ref.bin" "$TMP/k0.tamper.bin" "$TMP/k0.hxp1" 2>&1) || rc_tamp=$?
[ "$rc_tamp" -eq 12 ] || {
    echo "FAIL q38_sass_parity: tamper negative control expected exit 12, got $rc_tamp ($tamp_out)" >&2
    exit 1
}
echo "  control digest_tamper: PASS (exit=12: $tamp_out)"

rc_shave=0
shave_out=$("$TMP/monk_check" "$TMP/k0.ref.bin" "$TMP/k0.shave.bin" "$TMP/k0.shave.hxp1" 2>&1) || rc_shave=$?
[ "$rc_shave" -eq 17 ] || {
    echo "FAIL q38_sass_parity: stall_shave negative control expected exit 17, got $rc_shave ($shave_out)" >&2
    exit 1
}
echo "  control stall_shave: PASS (exit=17: $shave_out)"

BYTES=$(wc -c < "$TMP/enc_gpu.sass" | tr -d ' ')
OM_SHA=$(hash_file "$TMP/enc_gpu.sass")
echo "PASS q38_sass_parity: 7/7 Qwen3.8-27B sm_121 kernels bit-exact (bw_enc_sm121 == gpu/nvidia/om/encoder/bw_enc_sm121), 5x 2x-det PASS, 7/7 MONK PASS, 2/2 red controls caught (${BYTES} bytes, sha256=${OM_SHA})"
