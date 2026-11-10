/-
LongNames.lean: the packed-word argument of omc's long names (docs/one_layer/OMEGESE.md 9.2), as a model.

omc compares names by a 64-bit packed word: the first 8 bytes of the word, little-endian. tok2 gives a
name of 9..63 bytes the packed word 1 + 256 * k instead, k its index in the intern table. The claims:

  1. a packed word's low byte is the word's first byte, which is 33..255 (tok2 ends a word at a byte
     of 32 or less, and tok refuses a byte below 32 with error 16);
  2. so no packed word of a real word (any name of 8 bytes or fewer, any keyword, or the first 8 bytes
     of a longer word) equals an interned word, whose low byte is 1;
  3. distinct table indices give distinct interned words.

Model scope: bytes are natural numbers, a packed word is `pack` of at most 8 of them, and the 64-bit
width is not modelled (8 bytes fit in 64 bits; an index below 4096 keeps 1 + 256 k below 2^20). The
intern table itself (one index per spelling) and its hash probing are not modelled here; they are
exercised by long_alias.om, long_63.om and long_names.om beside this file and by the interning
mutants and capacity check of seed/omc/gate-longnames.sh.

Status: written for Lean 4 core, no Mathlib. CHECKED 2026-11-08 on the Spark (AArch64) with
leanprover/lean4:v4.35.0: `lean seed/omc/tests/longnames/LongNames.lean` printed nothing and exited 0, and
`#print axioms` for each of interned_low, pack_low, pack_ne_interned, pack_take8_ne_interned and
interned_inj lists only [propext, Quot.sound], no `sorryAx`. To recheck: the same two steps.
-/

/-- The packed word of a byte list, least significant byte first. -/
def pack : List Nat → Nat
  | [] => 0
  | b :: rest => b + 256 * pack rest

/-- The packed word tok2 gives the long name at table index k. -/
def interned (k : Nat) : Nat := 1 + 256 * k

theorem interned_low (k : Nat) : interned k % 256 = 1 := by
  unfold interned
  omega

theorem pack_low (b : Nat) (rest : List Nat) (hb : b < 256) :
    pack (b :: rest) % 256 = b := by
  simp only [pack]
  omega

/-- Claim 2 for a word with first byte b: its packed word is never an interned word. -/
theorem pack_ne_interned (b : Nat) (rest : List Nat) (k : Nat)
    (hlo : 33 ≤ b) (hhi : b < 256) : pack (b :: rest) ≠ interned k := by
  intro h
  have h1 := pack_low b rest hhi
  have h2 := interned_low k
  rw [h] at h1
  omega

/-- Claim 2 for any nonempty word of bytes 33..255: omc packs its first 8 bytes. -/
theorem pack_take8_ne_interned (w : List Nat) (k : Nat) (hne : w ≠ [])
    (hbytes : ∀ b, b ∈ w → 33 ≤ b ∧ b < 256) : pack (w.take 8) ≠ interned k := by
  cases w with
  | nil => exact absurd rfl hne
  | cons b rest =>
    have hb := hbytes b (by simp)
    show pack (b :: rest.take 7) ≠ interned k
    exact pack_ne_interned b (rest.take 7) k hb.1 hb.2

/-- Claim 3: distinct indices, distinct interned words. -/
theorem interned_inj (j k : Nat) (h : interned j = interned k) : j = k := by
  unfold interned at h
  omega
