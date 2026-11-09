OM-2 qualification leakage lane (#748, L836): contract §8 evidence (a), revised by E11/E12/E13.
All implementation is handwritten seeded OM-1 Omega in leakscan.om. External objdump/Python are
oracles only (../oracle/leak/PROVENANCE.txt). No compiler-lane or SHA-lane source was read.

Build/run (repository root)
  seed/out/omc < seed/qualification/om2/leak/leakscan.om > build/om2-qual/leakscan-e13
  chmod +x build/om2-qual/leakscan-e13
  build/om2-qual/leakscan-e13 [xN | pub:SLOT:OFF:LEN ...] < ARTIFACT
N/SLOT are entry parameter slots 0..5. xN marks DATA; otherwise entry parameters are public pointers,
lengths/opcodes. pub declares initially public bytes [OFF,OFF+LEN) relative to that entry pointer.
Up to 32 ranges, nonnegative decimal OFF/LEN with sum <= 2^55-1. An incorrect initial declaration is
an unsupported caller assertion. E13 checks preservation: a DATA or unclassified store that may hit
the range REVOKES it; secret stores are not excused as a caller assertion violation.
Exit: 0 PASS; 1 FAIL (data-index with no MANUAL); 2 NOT_RUN (any MANUAL, UNKNOWN or UNHANDLED);
90 invalid argv; 91 malformed artifact (empty, ELF, partial word, over 8 MiB); 92 worklist limit;
93 output I/O failure. NOT_RUN is never PASS.

Output
  @N means word offset N, byte offset 4N. Entry word 0 (or its direct B to the last function).
  BRANCH @N mnemonic ->@target len | data never-taken-trap-check | data MANUAL [trap=code]
  MEM @N mnemonic form base=reg index=reg const | public-index | data-index | unreached
  PUBLIC-DECL SLOT+OFF:LEN
  PUBLIC-MEM @N public-mem SLOT+OFF       EVERY load the declaration classifies public is listed here.
  PUBLIC-MEM-REVOKED @N public-mem SLOT+OFF:LEN   potentially poisoning store (or unclassified word).
  UNKNOWN @N 0xword; UNHANDLED @N reason; SUMMARY class counts; VERDICT TRACE-EQUIV-STATIC ...
The legacy summary field trap-check counts only E12 PROVED checks; data-branch counts MANUAL branches
(trap targets included). MANUAL-ITEMS enumerates UNKNOWN/UNHANDLED; data MANUAL branches are listed
individually and counted in data-branch. All conditional branches are listed, including B.AL/NV.
All memory accesses with a base other than SP/FP, or any register index, are listed. SP+immediate
spill slots are modeled but not listed. Literal-pool loads are public, not an indexed address.

E12 safety correction (supersedes the original structural trap rule)
A branch to a trap stub is NOT sufficient proof that it is never taken. Required negative control:
  fn f a view ulong 4 to uint / ret uint get a 0 / end
This scans data MANUAL trap=5, verdict NOT_RUN. Native program-mode twins reachable-zero.om and
reachable-big.om execute that same loaded conversion with 0 and 2^32: gate checks exits 0 and 105.
Only a conversion CBNZ-to-trap whose check register is proven zero through an AND with a known
constant mask can be discharged. We track known-zero bits for GPRs: constants, MOVK, AND-immediate
(Arm DecodeBitMasks) or AND-register, copies and UBFM/LSR. AND-proof provenance must survive to the
check; canonicalization of a loaded narrow value alone is not an AND proof. Joins intersect zero
bits and proof bits. CBNZ with all bits known zero and AND provenance is data never-taken-trap-check.
The positive trap-check.om uses AND 0xffffffff followed by LSR #32; it remains PASS.
Other DATA branches, including structurally identified trap edges, are MANUAL and force NOT_RUN.
Memory data-index still fails absent a MANUAL item. Speculative execution, latency and caches are
outside the claim (§8 lines 239-241). This is finite static evidence, not a mechanized proof.

Decode subset (main acb3f15 omc emission, no candidate source dependency)
- B/BL; B.cond; CBZ/CBNZ; TBZ/TBNZ; RET/BR/BLR; SVC; NOP/DSB.
- ADD/SUB(S) immediate, shifted and extended; logical immediate and shifted-register; MOVZ/N/K;
  SBFM/BFM/UBFM; ADR/ADRP; ADC/SBC, CCMP/CCMN, CSEL/CSINC/CSINV/CSNEG (CSET alias).
- UDIV/SDIV, LSLV/LSRV/ASRV/RORV, RBIT/REV/CLZ/CLS, MADD/MSUB and widening/high multiply.
- EXTR/ROR-immediate, RORV and NEG were already covered by the instruction classes; the independent
  citations are Arm DDI0487M.d C6.2.160 p2201 (EXTR), C6.2.349 p2580 (RORV, DP2 opcode 11), and
  C6.2.295 p2475 (NEG = SUB from XZR, not SP). No S1 source was consulted.
- Scalar FP moves/conversions, one/two-source ops and comparisons, single/double precision.
- Loads/stores: unsigned immediate, register offset (UXTW/UXTX/SXTW/SXTX + scale), unscaled/pre/post,
  LDP/STP/LDPSW and LDR literal. Reserved/unallocated patterns are UNKNOWN, including invalid sf/N,
  logical masks, shifts, opcode/type fields, PRFM, and constrained-unpredictable writeback aliases.
Om1 emission references: omc.om ldop/stop 1321/1354; e3 1498; matconst 1568; canon 1595; cset 1653;
bo_* 1894-2083; scalar FP 2088-2355; save/loadarg/restore 2460-2524; elemaddr 2547; finish 5633-5670.
SIMD/SVE, atomics/exclusives, system-register instructions and other encodings are UNKNOWN.

Taint/CFG rules
- May-DATA bits for x0..x30, NZCV and v0..v31, OR at joins. Flag-setting ops REPLACE NZCV taint by
  sources; CSET/CSEL/ADC/CCMP read flags. Memory values DATA except literal loads, tracked spill slots
  and proven declared-public loads. Entry x7/runtime and x30/return address public; other nonparameter
  registers and flags start DATA. Constants/ADR/ADRP/zero-register public.
- Worklist to fixpoint; conditional branches have both successors (AL/NV only target). Direct calls
  join caller argument/register states into callee entry. Each RET joins into an exit summary, which
  requeues reached callers. Registers/flags after BL come from the callee summary; caller spill state
  is restored separately. This is context-insensitive: distinct call sites lose differing constants.
- SP depth and current 64 eight-byte spill slots are modeled. omc save/restore lowers SP, spills all
  live pool registers + x30, reloads args, BLs, reloads preserved values and releases the frame.
  Spill loads carry saved taint AND exact pointer/constant provenance, not unconditional DATA.
- SP writes other than ADD/SUB SP,SP,#imm, SP writeback, accesses outside the current frame, mismatched
  depths/functions, nonzero RET depth, DATA x30, indirect BR/BLR, SVC, out-of-artifact flow or writes
  to x7 are UNHANDLED and force NOT_RUN. Exact-provenance record exhaustion also does (provenance-cap).
- omc invariant A1: computed-base array writes never alias spill slots. Arrays precede calls on the
  stack, spill areas are below them, and runtime/compile-time index checks prevent cross-array writes
  (sa_arr 4922, elemaddr 2547). This invariant is assumed, not re-proved for arbitrary machine bytes.
- The trap shape is MOVZ X1,#1..14; B to MOV X0,X7; LDR X16,[X7,#16]; BR X16. Those paths terminate;
  the runtime trap is assumed nonreturning. Shape identifies the trap target, NOT its unreachability.

Public-memory provenance / P1 resolution
Each GPR carries unknown, an exact signed constant, or original-entry-slot base + exact constant.
MOV, ADD/SUB immediate and ADD/SUB register with constant shifted/extended operand propagate it;
MOVZ/N/K build constants. Narrowing a pointer loses its identity. Spill slots, function inputs and
exit summaries carry the same domain. Unequal provenance joins to unknown. No intervals, loop
induction or call specialization. Constants/offsets outside signed 56 bits are conservatively unknown.
Whole aligned eight-byte spills preserve identity; partial stores invalidate every overlapping slot.
All bytes of a load (both elements of a pair) must fit a declaration; no wrap or one-past-end admission.
P1 uses explicit declarations, never an implicit blanket memory declassification. E13 also requires
the declared range to survive the store scan below. Current OM-1 SHA getle(c,p,nb) shares call sites
and loops over p+i, so its count loads remain unknown in this exact domain even without revocation.
With E13, pub:0:32:8 is conservatively revoked by 68 stores. Its 15 original count-derived items
remain listed for manual classification, not passed; E12 adds nine unproved DATA trap checks.
Result: ten discharged checks, 16 MANUAL branches, eight data-index accesses, NOT_RUN. See notes.

E13 preservation check (sound whole-artifact fallback, not flow-sensitive memory contents)
After CFG fixpoint, inspect EVERY word, including stores with no reached state. A DATA value or
address, unreached/unclassified store, UNKNOWN instruction or UNHANDLED construct is potentially
poisoning. An unknown base/address may hit every nonempty declaration; different entry-slot roots
are not assumed disjoint. A store is proven outside only when exact same-slot byte extents do not
overlap, or when it is a proven current-frame SP+immediate spill (existing A1 frame-separation rule).
Classified public-value/public-address stores are length-dependent and do not revoke declarations.
For every poisoning word/range pair, record PUBLIC-MEM-REVOKED with its word offset. Revoke the
whole range for the entire scan, including earlier loads; reset taint, provenance and summaries,
and rerun to fixpoint. Repeat until no new range is revoked (at most 32 revocations). This also
handles stores whose DATA dependencies are revealed only by a prior declaration revocation.
Public-load annotations come only from the final analysis, never from a provisional pass.
pub-secret.om pins the reported E13 false PASS; pub-unknown.om pins unknown-address revocation;
pub-outside-store.om proves a secret store at byte40 does not poison public [32,40). Native drivers
pub-secret-zero/one concatenate with the same function and execute exits0/1, showing different paths.
Dynamic traces and the OM-2 SHA artifact remain NOT_RUN here.

E14 precision rules (L1039, opt-in argument e14; without e14 every statement above holds unchanged)
  build/om2-qual/leakscan [xN | pub:SLOT:OFF:LEN ...] e14 < ARTIFACT     (e14 in any argument position)
E13 revokes a declaration on any poisoning store in the whole artifact. With e14 the walk is the same, but
a poisoning store is excused when exactly one of three rules proves it cannot touch the declaration. Each
excused store is printed as PUBLIC-EXCUSED @N RULE and counted on the line
  E14 excused unreached=A stack=B bounded=C
A store that no rule excuses revokes exactly as in E13 (PUBLIC-MEM-REVOKED). Output without e14 has neither
line. The three rules (every other store, and every UNKNOWN or UNHANDLED reached word, still revokes):
 1 unreached-from-entry. The word has no state: no execution of THIS entry reaches it (it belongs to another
   export or to dead code). Sound only together with the all-exports obligation, printed as PUBLIC-OBLIGATION
   whenever A > 0: the declaration is true at the entry of every call, by induction over call sequences, only
   if every export that can write the declared range is scanned with the same declaration and none reports
   PUBLIC-MEM-REVOKED. One run scans one entry; which exports belong to the obligation is decided by the
   driver, not by the scanner. sha-exports.sh runs every export of the SHA artifact and prints MET or NOT_MET.
   The pair e14-unreached.om / e14-other-export.om is one set of functions with the entry swapped: the store
   is excused from f and revokes from g. sha-exports.sh leaves `hash` out of the obligation because it takes no
   pointer to ctx: it could write the declared field only through an `out` pointer the caller aliased to ctx.
   That exclusion is an ASSUMPTION of the same kind as the one final needs (PROPOSAL-E14-final-out.txt): it is
   not proved by the scanner and stays open until L835 / Drake decide.
 2 stack-below-entry-sp. R is the SP at entry of the scanned export. Token 8 is an INTERVAL l..u on an address
   relative to R (address in R+l .. R+u, 24-bit signed bounds, deeper than 8 MiB is unknown). The SP starts at
   [0,0]; SUB/ADD SP move it; ADD Xd,SP,#imm and sums with constants or value ranges move the interval through
   registers, spill slots, call arguments and returns; joins keep the hull (at most 250 widenings, then
   unknown). rvsplo takes Lmin, the lowest SP lower bound over every reached word (unknown if any reached word
   has no SP interval). A store is excused only when BOTH u + displacement + index high + size <= 0 (its last
   byte is below R) AND l + displacement + index low >= Lmin (its first byte is in memory the SP register has
   covered during the walk). That is exactly the memory the existing SP+immediate spill exemption trusts
   (slotok: between the SP and the function's entry SP), generalised from SP+immediate addressing to pointers
   computed from SP. Without the lower bound, a pointer such as SP - 0x2aaa00000000 would be excused although
   it is a heap address (L1039 review P1; e14-stack-far.S, e14-stack-far2.S). It is NOT the A1 array-bounds
   invariant: no array length is assumed for a pointer passed between functions or for a layout field. A
   callee that writes beyond the array the caller passed reaches R or higher (e14-stack-over.S: SP+16 = R) or
   below the lowest SP (e14-stack-below.S: SP-1) and revokes.
 3 bounded-offset. The address is an exact entry-slot token plus displacement plus an index register whose
   value range lo..hi is known (token 9, 24-bit bounds). Ranges come from constants, known-zero masks (AND
   with a mask), sums of ranges and constants, and a dominating check: CMP Xn,#imm or CMP Xn,Xm (64 bit)
   followed by B.CS/B.CC/B.HI/B.LS narrows Xn on each edge (the usual put/get bounds check, B.CS to the trap
   stub). The flag source is dropped when the flags or Xn (or Xm) are written before the branch, at BL,
   and unless both paths agree at a join. The store is excused for a declaration when its highest start
   offset + size <= the declaration's offset, or its lowest start offset >= the declaration's end, in the
   same entry slot. An unknown or overlapping range, a pre/post-index store, or another slot revokes.
Not added: any disjointness between different entry slots. The 32 digest bytes that final stores through
its `out` pointer still revoke pub:0:32:8 (PROPOSAL-E14-final-out.txt names the trust change that would be
needed). e14 also stops treating ADD Xd,SP,Xm,ext as a constant (Rn 31 is SP there, in both modes).
E14 fixtures (leak/fixtures, expected reports in leak/expected, gate rows in leak.cases and candidate.cases):
e14-stack.om stack positive; e14-stack-edge.S last byte of a 16-byte array (SP+15) positive; e14-stack-low.S
first byte [SP] positive; e14-stack-over.S SP+16 negative; e14-stack-below.S SP-1 negative; e14-stack-far.S
and e14-stack-far2.S SP minus a huge or an 8 MiB constant negative; e14-bounded.om c[40+(i&63)] positive;
e14-bounded-low.om c[i&127] negative; e14-refine.om dominating check then c[40+i] positive; e14-refine-edge.om
check i<32 then c[i] positive at the edge; e14-refine-low.om c[33+i] negative; e14-unreached.om /
e14-other-export.om; e14-flag-ok.S positive and e14-stale-reg.S / e14-stale-flags.S negatives; pub-secret.bin
and pub-unknown.bin rescanned with e14 still revoke. The .S fixtures are hand-assembled with GNU as 2.42
(aarch64-linux-gnu-as, objcopy -O binary -j .text; oracle only; not part of the delivered closure) because
omc type-checks array sizes across calls and cannot express a callee that outruns the caller's array. E14
expected reports were produced by this scanner and then checked against objdump 2.42 offsets
(oracle/leak/xcheck.py AGREE for every one) and against the premises written in each fixture's header; they
are not hand-derived from construction like the E13 set.
Mutants (leak/mutants, exact once, killed by the named fixture): e14nostack/e14edge (stack upper bound removed
or off by one byte) by e14-stack-over, e14nolow8 (stack lower bound removed) by e14-stack-far2/-below (e14-stack-far.S is refused earlier: -0x2aaa00000000 does not fit the 24-bit stack interval),
e14noreach by e14-other-export, e14nolow by e14-bounded-low, e14off1 by e14-refine-edge, e14norefine by
e14-refine, e14noclearreg/e14noclearflags by e14-stale-reg/-flags.

Cases/evidence (all paths relative to seed/qualification/om2)
leak/leak.cases runs now under 734f0a39; leak/candidate.cases runs common cases under a candidate and
compiles s1-rot.om. Binary input identities are in leak.cases; expected reports are hand-derived from
construction and objdump offsets, not copied as behavioral truth from a compiler under test.
evidence/phaseB/leak-pinned.log and leak-candidate-s1.log record gates; leak-sha256-om1.txt and
leak-sha256-om1-pub.txt hold full corrected scans; leak-s1-rot.txt records source/artifact identities,
scan and objdump cross-check. leak-reachability.txt records both E12 and E13 native control outcomes.
leak-corpus-xcheck.txt: 31 baseline function-mode units cross-checked. leak-fuzz.txt: historical decoder
fuzz before E12; decoder classes unchanged, not evidence for the added provenance/known-bits analysis.

Mutant kills (exact exits plus stdout differs from the corresponding expected report)
cbtaint/trap-check: exit0, check mislabeled len; loadpub/data-branch: exit0 false PASS;
callexit/call-data: exit0 false PASS; slotoff/call-public: exit2 ret-x30-data;
flagsweak/flags: exit2, public compare wrongly DATA; nostub/trap-check: exit2 br-indirect;
pubrange/public-out: exit0 false PASS because one-past-end byte incorrectly declared public.
norevoke/pub-secret: exit0 false PASS when the E13 store scan is omitted; must differ from NOT_RUN.
Native-reachability controls pin the earlier false-PASS defect. Candidate compiler leak mutants
must produce a new MANUAL branch, data-index, UNKNOWN or UNHANDLED item; they are never accepted
as PASS. Removing unroll is not a leak mutant (constant-bound loop branches remain public).

E14 evidence (leak/evidence-e14, 2026-11-09, omc seed/out/omc 6d1b1cf5): identity.txt (scanner and artifact
hashes), gate-*-baseline-main.log (this directory's cases at main before the change), gate-*-patched.log (after),
default-mode-compare.txt (old and new scanner byte-identical on every fixture, the SHA exports and the SHA
artifact under no argument, pub:0:32:8, x0 and pub:1:0:16 x2), sha-exports/ (four export reports, objdump
cross-checks, summary.txt with the all-exports obligation). Pre-existing at main, unchanged by E14: row
s1-rot-refused FAILS (omc 6d1b1cf5 accepts the OM-2 opt-in on line 1 that omc 734f0a39 refused; the row
belongs to the compiler lane's pin, not to the scanner). Replay (repository root, under the pool lock):
  sh seed/qualification/om2/leak/sha-exports.sh build/om2-qual/leakscan-e14 build/om2-qual/sha.bin OUTDIR
