#!/usr/bin/env bash
# ck_spinlock_asm_check.sh A64.dis X86.dis PIPE_A64.dis -- reads `objdump -drt` of native/kernel/tests/spinlock_tu.c
# built freestanding for aarch64 and x86-64, and of native/kernel/core/pipe.c built for the aarch64 kernel (make
# spinlock-asm-check, DRA-556). It follows each function's registers (symbol or argument + offset, and where each
# value came from: the saved DAIF/RFLAGS, or a load from which field) and checks the orders core/spinlock.h promises
# on the fields they name (ticket +0, serving +4, irq +8 of struct ck_spinlock):
#   ck_spin_asm_locked (ck_spin_lock_irqsave / ck_spin_unlock_irqrestore on ck_spin_asm_lock)
#     aarch64  mrs daif < msr daifset #3 < ticket atomic on +0 < acquire load of +4 ; stlr to +4 < msr daif, and
#              the register msr daif writes back is the one mrs read;
#     x86-64   pushf/pop < cli < lock xadd on +0 < load of +4 ; store to +4 < sti, and the IF test before sti reads
#              the register pop filled.
#   ck_spin_asm_slot_lock / ck_spin_asm_slot_unlock (ck_spin_lock / ck_spin_unlock on ck_spin_asm_slot, the form
#   core/pipe.c uses: the saved state lives in l->irq)
#     lock     the same acquire order, then the saved state is stored to +8 after the acquire load (after entry);
#     unlock   the state restored (msr daif / the IF test before sti) was loaded from +8 before the store to +4.
#   every lock site of core/pipe.c (aarch64): one mrs daif before each msr daifset #3 and a ticket atomic after it;
#     as many releasing stlr as msr daif restores; between each stlr and the next msr daif no branch and no branch
#     target, and the register restored was the mrs value or a load from the released lock's +8 field, made before
#     the stlr ("load or forward l->irq before the stlr"); every store of a mrs value (l->irq = f) comes after an
#     acquire load that follows that mrs (after entry).
# Last line: CK_SPINLOCK_ASM: PASS|FAIL. --selftest A64.dis X86.dis PIPE_A64.dis mutates the dumps (instructions
# moved with their relocations) and requires each mutant to FAIL by the rule it targets.
set -uo pipefail
me=$0

# ---- annotate ARCH DUMP FUNC: one tab-separated line per instruction of FUNC:
#   idx op mem dst srcorig addr btarget args
# mem: the address an access touches, "sym+off" (or "A0+off" for the first argument); dst: the register written;
# srcorig: for a store the origin of the stored register, for msr daif and the x86 IF test the origin of the register
# read: "M@i" (mrs daif at idx i), "F@i" (pushf/pop at i), "L@i:mem" (loaded at i from mem), "?" unknown.
annotate() {
    awk -v arch="$1" -v fn="$3" -F'\n' '
    function hex(s,   n, i, c, neg) { neg = 0; if (s ~ /^-/) { neg = 1; s = substr(s, 2) }
        sub(/^0x/, "", s); n = 0; for (i = 1; i <= length(s); i++) { c = index("0123456789abcdef", substr(s, i, 1)) - 1; n = n * 16 + c }
        return neg ? -n : n }
    function num(s) { return (s ~ /^-?0x/) ? hex(s) : s + 0 }
    # reloc target "name", "name+0x4", "name-0x4" -> base in RB, addend returned
    function target(t,   m) { if (match(t, /[+-]0x[0-9a-f]+$/)) { RB = substr(t, 1, RSTART - 1); return hex(substr(t, RSTART + (substr(t, RSTART, 1) == "+"))) } RB = t; return 0 }
    # resolve base+off to symbol+field when base is a section
    function resolve(b, o,   k) { if (b == "") return "-"
        if (b ~ /^\./) { for (k in sv) if (ss[k] == b && o >= sv[k] && o < sv[k] + sz[k]) return k "+" (o - sv[k]); return b "+" o }
        return b "+" o }
    function areg(r) { if (r ~ /^[wx][0-9]+$/) return "r" substr(r, 2); return r }
    function xreg(r) { sub(/^%/, "", r)
        if (r ~ /^(rax|eax|ax|al|ah)$/) return "a"; if (r ~ /^(rbx|ebx|bx|bl|bh)$/) return "b"
        if (r ~ /^(rcx|ecx|cx|cl|ch)$/) return "c"; if (r ~ /^(rdx|edx|dx|dl|dh)$/) return "d"
        if (r ~ /^(rsi|esi|si|sil)$/) return "si"; if (r ~ /^(rdi|edi|di|dil)$/) return "di"
        if (r ~ /^(rbp|ebp|bp|bpl)$/) return "bp"; if (r ~ /^(rsp|esp|sp|spl)$/) return "sp"
        if (r ~ /^r[0-9]+[dwb]?$/) { sub(/[dwb]$/, "", r); return r } return "" }
    # unknown = "" (no delete: gawk 5.2.1 crashes deleting these elements in this program; mawk does not)
    function clr(r) { if (r != "") { vb[r] = ""; vo[r] = 0; org[r] = "?" } }
    function og(r) { return (r in org) ? org[r] : "?" }
    # split operands at top-level commas (not inside [] or ()) into the global X; returns their count
    function ops(s,   n, d, i, c, cur, t) { n = 0; d = 0; cur = ""; split("", X)
        for (i = 1; i <= length(s); i++) { c = substr(s, i, 1)
            if (c == "[" || c == "(") d++; if (c == "]" || c == ")") d--
            if (c == "," && d == 0) { t = cur; gsub(/^ +| +$/, "", t); X[++n] = t; cur = ""; continue } cur = cur c }
        if (cur != "") { t = cur; gsub(/^ +| +$/, "", t); X[++n] = t } return n }
    /^SYMBOL TABLE:/ { insym = 1; next }
    insym && NF == 0 { insym = 0 }
    insym { n = split($0, f, /[ \t]+/); for (i = 2; i < n; i++) if (f[i] ~ /^\./ && f[i + 1] ~ /^[0-9a-f]+$/ && length(f[i + 1]) >= 8) {
                if (f[n] !~ /^\./) { sv[f[n]] = hex(f[1]); sz[f[n]] = hex(f[i + 1]); ss[f[n]] = f[i] } break }
            next }
    $0 ~ ("^[0-9a-f]+ <" fn ">:$") { on = 1; next }
    on && /^$/ { on = 0 }
    !on { next }
    /^[ \t]+[0-9a-f]+: R_/ { split($0, f, /[ \t]+/); for (i = 1; i <= length(f); i++) if (f[i] ~ /^R_/) { rt[n_i] = f[i + 1]; rp[n_i] = hex(substr(f[i - 1], 1, length(f[i - 1]) - 1)) } next }
    {
        line = $0
        if (arch == "a64") {
            if (!match(line, /^ +[0-9a-f]+:\t[0-9a-f]{8} \t/)) next
            n_i++; split(line, f, "\t"); a_ = f[1]; gsub(/[ :]/, "", a_); ad[n_i] = hex(a_); op[n_i] = f[3]; ar[n_i] = f[4]
            sub(/[ \t]*\/\/.*$/, "", ar[n_i])
        } else {
            if (!match(line, /^ +[0-9a-f]+:\t/)) next
            split(line, f, "\t"); nb = split(f[2], by, " ")
            if (length(f) < 3 || f[3] == "") { ln[n_i] += nb; next }   # continuation bytes
            n_i++; a_ = f[1]; gsub(/[ :]/, "", a_); ad[n_i] = hex(a_); ln[n_i] = nb
            m = f[3]; sub(/[ \t]*#.*$/, "", m); sub(/ +$/, "", m); if (m ~ /^lock /) { sub(/^lock +/, "", m); m = "lock_" m }
            op[n_i] = m; sub(/ .*/, "", op[n_i]); ar[n_i] = m; sub(/^[^ ]+ */, "", ar[n_i])
        }
    }
    END {
        if (arch == "a64") { org["r0"] = "?"; vb["r0"] = "A0"; vo["r0"] = 0 }
        else { vb["c"] = "A0"; vo["c"] = 0 }           # -mabi=ms: first argument in rcx
        flags = ""
        for (i = 1; i <= n_i; i++) {
            o = op[i]; a = ar[i]; mem = "-"; dst = "-"; so = "-"; bt = "-"; k = ops(a)
            if (arch == "a64") {
                if (o ~ /^(b|b\..*|bl|cbz|cbnz|tbz|tbnz)$/) { if (match(a, /[0-9a-f]+ </)) bt = hex(substr(a, RSTART, RLENGTH - 2)) }
                if (o == "bl") { for (r = 0; r <= 18; r++) clr("r" r); clr("r30") }
                mi = 0; for (j = 1; j <= k; j++) if (X[j] ~ /^\[/) mi = j
                if (mi) { mm = X[mi]; post = (mi < k && X[mi + 1] ~ /^#/ && mm !~ /,/)
                    gsub(/[\[\]!]/, "", mm); split(mm, P, /, */); b = areg(P[1]); off = (P[2] != "" && !post) ? num(substr(P[2], 2)) : 0
                    if (vb[b] != "") mem = resolve(vb[b], vo[b] + off) }
                if (o == "adrp") { d = areg(X[1]); clr(d); if (i in rt) { off = target(rt[i]); vb[d] = RB; vo[d] = off } }
                else if ((o == "add" || o == "sub") && (k == 3 || (k == 4 && X[4] == "lsl #12")) && X[3] ~ /^#/) { d = areg(X[1]); s = areg(X[2])
                    im = num(substr(X[3], 2)) * (k == 4 ? 4096 : 1)
                    if (i in rt) { off = target(rt[i]); nb_ = RB; clr(d); vb[d] = nb_; vo[d] = off }
                    else if (vb[s] != "") { nb_ = vb[s]; no_ = vo[s] + (o == "add" ? 1 : -1) * im; clr(d); vb[d] = nb_; vo[d] = no_ }
                    else clr(d) }
                else if (o == "mov" && k == 2 && X[2] ~ /^[wx][0-9]+$|^sp$/) { d = areg(X[1]); s = areg(X[2]); b_ = vb[s]; o_ = vo[s]; g = og(s); clr(d); vb[d] = b_; vo[d] = o_; org[d] = g }
                else if (o == "mrs") { d = areg(X[1]); clr(d); if (X[2] == "daif") org[d] = "M@" i }
                else if (o == "msr") { if (X[1] == "daif") so = og(areg(X[2])) }
                else if (o ~ /^ld(add|clr|set|eor|swp)/ || o ~ /^(swp|cas)/) { dst = areg(X[k - 1]); if (o ~ /^cas/) dst = areg(X[1]); clr(dst) }
                else if (o ~ /^ld/) { if (o ~ /^ldp/) { clr(areg(X[1])); clr(areg(X[2])) } else { dst = areg(X[1]); clr(dst); org[dst] = "L@" i ":" mem } }
                else if (o ~ /^st/) { if (o ~ /^st(l)?xr/) { clr(areg(X[1])); so = og(areg(X[2])) } else so = og(areg(X[1])) }
                else if (o !~ /^(cmp|cmn|tst|b|b\..*|bl|cbz|cbnz|tbz|tbnz|ret|nop|yield|dmb|dsb|isb|hint|prfm|msr)$/ && k >= 1) clr(areg(X[1]))
                if (mi && X[mi] ~ /!$/ || (mi && mi < k && X[mi + 1] ~ /^#/)) { mm = X[mi]; gsub(/[\[\]!]/, "", mm); split(mm, P, /, */); if (areg(P[1]) != "sp") clr(areg(P[1])) }
            } else {
                e = ad[i] + ln[i]
                if (o ~ /^(j[a-z]+|call)$/) { if (match(a, /^[0-9a-f]+ /)) bt = hex(substr(a, RSTART, RLENGTH - 1)) }
                if (o == "call") { clr("a"); clr("c"); clr("d"); clr("r8"); clr("r9"); clr("r10"); clr("r11") }
                mi = 0; for (j = 1; j <= k; j++) if (X[j] ~ /\(/) mi = j
                if (mi) { mm = X[mi]; disp = mm; sub(/\(.*/, "", disp); disp = (disp == "") ? 0 : num(disp); br = mm; sub(/.*\(/, "", br); sub(/[,)].*/, "", br)
                    if (br == "%rip" && (i in rt)) { off = target(rt[i]); mem = resolve(RB, off + (e - rp[i])) }
                    else if (vb[xreg(br)] != "") mem = resolve(vb[xreg(br)], vo[xreg(br)] + disp) }
                dr = (k >= 1) ? xreg(X[k]) : ""; sr = (k >= 2) ? xreg(X[1]) : ""
                if (o ~ /^pushf/) flags = i
                else if (o ~ /^pop/) { clr(dr); if (flags != "") org[dr] = "F@" i; flags = "" }
                else if (o ~ /^mov/ && mi == k) { so = og(sr) }                                  # store
                else if (o ~ /^mov/ && mi && mi < k) { clr(dr); dst = dr; org[dr] = "L@" i ":" mem }  # load
                else if (o ~ /^mov/ && sr != "") { b_ = vb[sr]; o_ = vo[sr]; g = og(sr); clr(dr); vb[dr] = b_; vo[dr] = o_; org[dr] = g }
                else if (o ~ /^lea/ && mi) { clr(dr); if (mem != "-") { split(mem, P, "+"); vb[dr] = P[1]; vo[dr] = P[2] + 0 } mem = "-" }
                else if (o ~ /^(test|and|bt)/) { so = og(dr); if (o ~ /^and/) clr(dr) }
                else if (o ~ /xadd|cmpxchg|xchg/) { if (sr != "") clr(sr) }
                else if (o !~ /^(cmp|j[a-z]+|call|ret|nop|pause|cli|sti|push)/ && dr != "" && mi != k) clr(dr)
            }
            printf "%d\t%s\t%s\t%s\t%s\t%d\t%s\t%s\n", i, o, mem, dst, so, ad[i], bt, a
        }
    }' "$2"
}

fail=0
pass_() { echo "PASS  $1"; }
fail_() { echo "FAIL  $1"; fail=1; }
# q ANN AWK-COND [last]: index of the first (or last) annotated line matching COND
q() { awk -F'\t' -v last="${3:-}" "($2){ r = \$1; if (!last) { print r; exit } } END { if (last && r != \"\") print r }" <<<"$1"; }
fld() { awk -F'\t' -v i="$2" -v c="$3" '$1 == i { print $c }' <<<"$1"; }
lt() { [[ -n "$2" && -n "$3" && "$2" -lt "$3" ]] && pass_ "$1 (instr $2 < $3)" || fail_ "$1 (instr '$2' '$3')"; }
is() { [[ "$2" == "$3" ]] && pass_ "$1" || fail_ "$1 (got '$2', want '$3')"; }

# acquire ARCH ANN LOCK NAME: the shared acquire order; sets SAVE and ACQ
acquire() {
    local a=$2 L=$3 n=$4 sv mk at
    if [[ $1 == a64 ]]; then
        sv=$(q "$a" '$2 == "mrs" && $8 ~ /, daif$/'); mk=$(q "$a" '$2 == "msr" && $8 ~ /^daifset, #0x3$/')
        at=$(q "$a" "\$2 ~ /^(ldxr|ldaxr|ldadd|cas|swp)/ && \$3 == \"$L+0\"")
        ACQ=$(q "$a" "\$1 > ${at:-0} && \$2 ~ /^ldar/ && \$3 == \"$L+4\"")
        lt "$n a64: DAIF saved before the mask" "$sv" "$mk"; SAVE="M@$sv"
    else
        sv=$(q "$a" '$2 == "pop" && $5 == "-"'); sv=$(awk -F'\t' '$2 ~ /^pop/ {print $1; exit}' <<<"$a")
        mk=$(q "$a" '$2 == "cli"'); at=$(q "$a" "\$2 ~ /xadd|cmpxchg/ && \$3 == \"$L+0\"")
        ACQ=$(q "$a" "\$1 > ${at:-0} && \$2 ~ /^mov/ && \$4 != \"-\" && \$3 == \"$L+4\"")
        lt "$n x86: RFLAGS saved (pushf/pop) before cli" "$sv" "$mk"; SAVE="F@$sv"
    fi
    lt "$n $1: mask before the ticket atomic on $L+0" "$mk" "$at"
    lt "$n $1: ticket atomic before the acquire load of $L+4" "$at" "$ACQ"
}
# release ARCH ANN LOCK NAME: sets REL (the releasing store to +4) and RESTORED (origin of the state put back)
release() {
    local a=$2 L=$3 n=$4 rs g
    if [[ $1 == a64 ]]; then
        REL=$(q "$a" "\$2 ~ /^stlr/ && \$3 == \"$L+4\"" last); rs=$(q "$a" '$2 == "msr" && $8 ~ /^daif, x/' last)
        RESTORED=$(fld "$a" "$rs" 5)
        lt "$n a64: releasing stlr to $L+4 before msr daif" "$REL" "$rs"
    else
        REL=$(q "$a" "\$2 ~ /^mov/ && \$4 == \"-\" && \$3 == \"$L+4\"" last); rs=$(q "$a" '$2 == "sti"' last)
        g=$(q "$a" "\$1 < ${rs:-0} && \$2 ~ /^(test|and|bt)/" last); RESTORED=$(fld "$a" "$g" 5)
        lt "$n x86: releasing store to $L+4 before sti" "$REL" "$rs"
    fi
}

tu() {  # tu ARCH DUMP
    local A arch=$1 st
    A=$(annotate "$arch" "$2" ck_spin_asm_locked)
    acquire "$arch" "$A" ck_spin_asm_lock pair; local save=$SAVE
    release "$arch" "$A" ck_spin_asm_lock pair
    is "pair $arch: the state restored is the one saved" "$RESTORED" "$save"
    A=$(annotate "$arch" "$2" ck_spin_asm_slot_lock)
    acquire "$arch" "$A" ck_spin_asm_slot slot
    st=$(q "$A" '$3 == "ck_spin_asm_slot+8" && $4 == "-" && $2 ~ /^(str|stur|mov)/')
    lt "slot $arch: l->irq (+8) stored after the acquire load (after entry)" "$ACQ" "$st"
    is "slot $arch: the state stored to l->irq is the one saved" "$(fld "$A" "$st" 5)" "$SAVE"
    A=$(annotate "$arch" "$2" ck_spin_asm_slot_unlock)
    release "$arch" "$A" ck_spin_asm_slot slot
    local ld=${RESTORED#L@}; ld=${ld%%:*}
    is "slot $arch: the state restored was loaded from l->irq (+8)" "${RESTORED#L@*:}" "ck_spin_asm_slot+8"
    lt "slot $arch: l->irq loaded before the releasing store" "${ld//[^0-9]/}" "$REL"
}

pipe() {  # every lock site of core/pipe.c, aarch64
    local d=$1 f A n_mk=0 n_rel=0 n_rs=0 n_st=0 n_ad=0 n_of=0 bad=0 msg
    for f in $(sed -n 's/^[0-9a-f]* <\([^>]*\)>:$/\1/p' "$d"); do
        A=$(annotate a64 "$d" "$f")
        msg=$(awk -F'\t' -v fn="$f" '
            { op[$1] = $2; mem[$1] = $3; so[$1] = $5; ad[$1] = $6; bt[$1] = $7; ar[$1] = $8; n = $1; if ($7 != "-") tg[$7] = 1 }
            END {
                for (i = 1; i <= n; i++) {
                    if (op[i] == "msr" && ar[i] ~ /^daifset, #0x3$/) { mk++
                        sv = 0; for (j = i - 1; j >= 1; j--) { if (op[j] == "msr" && ar[j] ~ /^daifset/) break; if (op[j] == "mrs" && ar[j] ~ /, daif$/) { sv = j; break } }
                        if (!sv) print "FAIL  pipe.c " fn ": msr daifset at instr " i " has no mrs daif before it"
                        at = 0; for (j = i + 1; j <= n; j++) { if (op[j] ~ /^(ldxr|ldaxr|ldadd|cas|swp)/) { at = j; break } if (op[j] ~ /^(ldar|stlr)/ || (op[j] == "msr" && ar[j] ~ /^daif/)) break }
                        if (!at) print "FAIL  pipe.c " fn ": no ticket atomic after the mask at instr " i }
                    if (op[i] ~ /^(ldxr|ldaxr|ldadd|cas|swp)/) { m_ = 0
                        for (j = i - 1; j >= 1; j--) { if (op[j] == "msr" && ar[j] ~ /^daifset, #0x3$/) { m_ = j; break } if (op[j] ~ /^stlr/ || (op[j] == "msr" && ar[j] ~ /^daif, x/)) break }
                        if (!m_) print "FAIL  pipe.c " fn ": ticket atomic at instr " i " has no msr daifset #3 before it" }
                    if (op[i] ~ /^stlr/) { rel++
                        rs = 0; for (j = i + 1; j <= n; j++) { if (op[j] == "msr" && ar[j] ~ /^daif, x/) { rs = j; break } if (bt[j] != "-" || op[j] == "ret") break }
                        if (!rs) { print "FAIL  pipe.c " fn ": stlr at instr " i " is not followed by msr daif without a branch between"; continue }
                        for (j = i + 1; j <= rs; j++) if (ad[j] in tg) print "FAIL  pipe.c " fn ": a branch lands between the stlr at " i " and its msr daif"
                        g = so[rs]; split(g, G, /[@:]/)
                        if (g ~ /^M@/) { if (G[2] + 0 >= i) print "FAIL  pipe.c " fn ": restored DAIF at " rs " read after the release at " i }
                        else if (g ~ /^L@/) {
                            if (G[2] + 0 >= i) print "FAIL  pipe.c " fn ": l->irq restored at " rs " was loaded at " G[2] ", after the release at " i
                            # Field: when both addresses are known, l->irq must be the released lock serving + 4;
                            # when the linear register tracking lost a base (paths joining), the load must still be
                            # [base, #8], the irq field of a struct ck_spinlock base.
                            split(mem[i], S, "+"); split(G[3], T, "+")
                            if (S[1] != "" && S[1] != "-" && T[1] != "" && T[1] != "-") {
                                if (S[1] != T[1] || T[2] - S[2] != 4) print "FAIL  pipe.c " fn ": state restored at " rs " came from " G[3] ", not the irq field of the lock released at " i " (" mem[i] ")"
                                else byaddr++
                            } else if (ar[G[2]] ~ /, #8\]$/) byoff++
                            else print "FAIL  pipe.c " fn ": state restored at " rs " was loaded at " G[2] " (" ar[G[2]] "), not from [base, #8]"
                        } else print "FAIL  pipe.c " fn ": state restored at " rs " has unknown origin " g }
                    if (op[i] == "msr" && ar[i] ~ /^daif, x/) rs_n++
                    if (op[i] ~ /^(str|stur)$/ && so[i] ~ /^M@/) { st++; split(so[i], G, /[@:]/)
                        ok = 0; for (j = G[2] + 1; j < i; j++) if (op[j] ~ /^ldar/) ok = 1
                        if (!ok) print "FAIL  pipe.c " fn ": the saved DAIF from instr " G[2] " is stored at " i " before any acquire load (before entry)" }
                }
                printf "COUNT %d %d %d %d %d %d\n", mk, rel, rs_n, st, byaddr, byoff
            }' <<<"$A")
        grep '^FAIL' <<<"$msg" && bad=1
        read -r _ a b c e g h <<<"$(grep '^COUNT' <<<"$msg")"
        n_mk=$((n_mk + a)); n_rel=$((n_rel + b)); n_rs=$((n_rs + c)); n_st=$((n_st + e)); n_ad=$((n_ad + g)); n_of=$((n_of + h))
    done
    [[ $bad == 0 ]] && pass_ "pipe.c a64: every mask, release, restore and l->irq store in order" || fail=1
    [[ $n_mk -ge 1 && $n_rel -ge 1 && $n_rel == "$n_rs" ]] && pass_ "pipe.c a64: $n_mk masks, $n_rel releasing stlr, $n_rs msr daif restores, $n_st l->irq stores; l->irq field by address at $n_ad sites, by [base, #8] at $n_of" \
        || fail_ "pipe.c a64: $n_mk masks, $n_rel releasing stlr, $n_rs msr daif restores (want at least one, and as many restores as releases)"
}

if [[ "${1:-}" == "--annotate" ]]; then annotate "$2" "$3" "$4"; exit; fi   # --annotate a64|x86 DUMP FUNC (debug)
if [[ "${1:-}" == "--selftest" ]]; then
    # Negative controls: each mutated dump must FAIL, and by the rule named. Mutations move whole instructions with
    # their relocation and continuation lines inside one function.
    shift; A=$1; X=$2; P=$3; t=$(mktemp -d); bad=0
    # mut FILE FUNC KIND PATA [PATB|FROM TO]: swap first block matching PATA with the last matching PATB; del: drop the
    # first block matching PATA; sub: replace FROM by TO in the first instruction line matching PATA; ins: insert
    # the line FROM before the first block matching PATA.
    mut() { awk -v fn="$2" -v kind="$3" -v pa="$4" -v pb="${5:-}" -v to="${6:-}" '
        { l[NR] = $0 }
        $0 ~ ("^[0-9a-f]+ <" fn ">:$") { on = 1; next }
        on && /^$/ { on = 0 }
        on && /^ +[0-9a-f]+:\t/ && $0 !~ /: R_/ && !(/^ +[0-9a-f]+:\t[0-9a-f ]+ *$/) { nb++; bs[nb] = NR }
        on { be[nb] = NR }
        END {
            for (b = 1; b <= nb; b++) { s = l[bs[b]]; if (s ~ pa && !i) i = b; if (pb != "" && s ~ pb) j = b }
            for (k = 1; k <= NR; k++) { blk[k] = 0 }
            if (!i) { print "mut: no block matches " pa > "/dev/stderr"; exit 1 }
            if (kind == "swap") { if (!j) { print "mut: no block matches " pb > "/dev/stderr"; exit 1 }
                for (k = 1; k <= NR; k++) {
                    if (k == bs[i]) { for (m = bs[j]; m <= be[j]; m++) print l[m]; k = be[i]; continue }
                    if (k == bs[j]) { for (m = bs[i]; m <= be[i]; m++) print l[m]; k = be[j]; continue }
                    print l[k] } }
            else for (k = 1; k <= NR; k++) {
                if (kind == "del" && k >= bs[i] && k <= be[i]) continue
                if (kind == "ins" && k == bs[i]) print pb
                if (kind == "sub" && k == bs[i]) { s = l[k]; sub(pb, to, s); print s; continue }
                print l[k] }
        }' "$1"; }
    neg() {  # neg NAME RULE-SUBSTRING A X P (a missing file is a mutation that did not apply)
        local f; for f in "$3" "$4" "$5"; do [[ -s $f ]] || { echo "NEG FAIL: $1: the mutation did not apply"; bad=1; return; }; done
        if bash "$me" "$3" "$4" "$5" > "$t/out" 2>&1; then cat "$t/out"; echo "NEG FAIL: $1 not caught"; bad=1
        elif grep -qF "CK_SPINLOCK_ASM: FAIL" "$t/out" && grep -F "FAIL  " "$t/out" | grep -qF -- "$2"; then echo "NEG PASS: $1 caught by: $2"
        else cat "$t/out"; echo "NEG FAIL: $1 not caught by '$2'"; bad=1; fi; }
    sp='[[:space:]]'
    nm=0
    m() { local out=$t/m$1; shift; mut "$@" > "$out" 2> "$out.err" || rm -f "$out"; echo "$out"; }
    # registers the mutants need, read from the dumps: the ticket base of the pair, the first restore of pipe.c
    tb=$(awk '/<ck_spin_asm_locked>:/{on=1;next} on&&/^$/{exit} on&&/\tldxr\t/{if (match($0, /\[x[0-9]+\]/)) print substr($0, RSTART, RLENGTH); exit}' "$A")
    neg "a64 pair: mask removed" "pair a64: mask before the ticket" "$(m 1 "$A" ck_spin_asm_locked del 'daifset')" "$X" "$P"
    neg "a64 pair: ticket atomic before mask" "pair a64: mask before the ticket" "$(m 2 "$A" ck_spin_asm_locked swap 'daifset' "${sp}ldxr$sp")" "$X" "$P"
    neg "a64 pair: restore before release" "pair a64: releasing stlr" "$(m 3 "$A" ck_spin_asm_locked swap "${sp}stlr$sp" "msr${sp}+daif, x")" "$X" "$P"
    neg "a64 pair: release store to the ticket" "pair a64: releasing stlr" "$(m 4 "$A" ck_spin_asm_locked sub "${sp}stlr$sp" '[[]x[0-9]+[]]' "$tb")" "$X" "$P"
    neg "a64 pair: restore from another register" "pair a64: the state restored" "$(m 5 "$A" ck_spin_asm_locked sub "msr${sp}+daif, x" 'x[0-9]+$' 'x9')" "$X" "$P"
    neg "a64 slot: l->irq stored before entry" "slot a64: l->irq (+8) stored after" "$(m 6 "$A" ck_spin_asm_slot_lock swap "${sp}ldxr$sp" "${sp}str${sp}.*#8[]]")" "$X" "$P"
    neg "a64 slot: l->irq loaded after the release" "slot a64: l->irq loaded before" "$(m 7 "$A" ck_spin_asm_slot_unlock swap "${sp}ldr${sp}x[0-9]+, [[]x[0-9]+, #32[]]" "${sp}stlr$sp")" "$X" "$P"
    neg "a64 slot: restore not from l->irq" "slot a64: the state restored was loaded" "$(m 8 "$A" ck_spin_asm_slot_unlock sub "msr${sp}+daif, x" 'x[0-9]+$' 'x0')" "$X" "$P"
    neg "x86 pair: cli removed" "pair x86: mask before the ticket" "$A" "$(m 9 "$X" ck_spin_asm_locked del "${sp}cli")" "$P"
    neg "x86 pair: xadd before cli" "pair x86: mask before the ticket" "$A" "$(m 10 "$X" ck_spin_asm_locked swap "${sp}cli" 'lock xadd')" "$P"
    neg "x86 pair: sti before the release" "pair x86: releasing store" "$A" "$(m 11 "$X" ck_spin_asm_locked swap "mov${sp}+%e[a-z]+,0x0[(]%rip[)]" "${sp}sti")" "$P"
    neg "x86 pair: IF test of another register" "pair x86: the state restored" "$A" "$(m 12 "$X" ck_spin_asm_locked sub "${sp}(test|and|bt)[a-z]*$sp" '%[a-z0-9]+$' '%r11')" "$P"
    neg "x86 slot: l->irq stored before entry" "slot x86: l->irq (+8) stored after" "$A" "$(m 13 "$X" ck_spin_asm_slot_lock swap 'lock xadd' "mov${sp}+%r[a-z0-9]+,0x0[(]%rip[)]")" "$P"
    neg "x86 slot: l->irq loaded after the release" "slot x86: l->irq loaded before" "$A" "$(m 14 "$X" ck_spin_asm_slot_unlock swap "mov${sp}+0x0[(]%rip[)],%r" "mov${sp}+%e[a-z]+,0x0[(]%rip[)]")" "$P"
    # pipe.c: the first function with a release; the register its first msr daif restores
    rf=$(sed -n 's/^[0-9a-f]* <\([^>]*\)>:$/\1/p' "$P" | while read -r f; do awk -v fn="$f" '$0 ~ ("^[0-9a-f]+ <" fn ">:$"){on=1;next} on&&/^$/{exit} on&&/\tstlr\t/{print fn; exit}' "$P"; done | head -n 1)
    rr=$(awk -v fn="$rf" '$0 ~ ("^[0-9a-f]+ <" fn ">:$"){on=1;next} on&&/^$/{exit} on&&/\tmsr\tdaif, x/{sub(/.*daif, /, ""); print; exit}' "$P")
    neg "pipe.c: l->irq reloaded after a release ($rf)" "pipe.c $rf: l->irq restored at" "$A" "$X" \
        "$(m 15 "$P" "$rf" ins "msr${sp}+daif, x" "$(printf '     ffc:\tf9400000 \tldr\t%s, [x19, #8]' "$rr")")"
    neg "pipe.c: a restore dropped ($rf)" "pipe.c" "$A" "$X" "$(m 16 "$P" "$rf" del "msr${sp}+daif, x")"
    neg "pipe.c: mask dropped ($rf)" "has no msr daifset #3 before it" "$A" "$X" "$(m 17 "$P" "$rf" del "daifset")"
    neg "pipe.c: l->irq stored before entry ($rf)" "before any acquire load" "$A" "$X" \
        "$(m 18 "$P" "$rf" swap "${sp}ldxr$sp" "${sp}str${sp}x[0-9]+, [[]x[0-9]+, #8[]]")"
    rm -rf "$t"; echo "CK_SPINLOCK_ASM_SELFTEST: $([[ $bad == 0 ]] && echo PASS || echo FAIL)"; exit $bad
fi

[[ $# == 3 ]] || { echo "usage: $0 A64.dis X86.dis PIPE_A64.dis | --selftest A64.dis X86.dis PIPE_A64.dis"; exit 2; }
tu a64 "$1"
tu x86 "$2"
pipe "$3"
echo "CK_SPINLOCK_ASM: $([[ $fail == 0 ]] && echo PASS || echo FAIL)"
exit $fail
