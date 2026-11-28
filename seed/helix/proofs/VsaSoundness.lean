/-
VsaSoundness.lean: Machine-checked Lean 4.36.0 formalization of 10,240-Bit
Vector-Symbolic Associative Program Memory (OMVSA1).

Zero external imports (pure Lean 4 core), verified with:
  ~/.elan/bin/lean -DwarningAsError=true seed/helix/proofs/VsaSoundness.lean
-/

namespace OmegaVsa

/-- Canonical OMVSA1 hypervector geometry: 160 × 64-bit lanes = 10,240 bits. -/
def omvsaWords : Nat := 160
def omvsaWordBits : Nat := 64
def omvsaDim : Nat := omvsaWords * omvsaWordBits

theorem omvsa_dim_eq : omvsaDim = 10240 := rfl

/-- Packed (word, bit) coordinates round-trip bijectively with flat bit index `i < 10240`. -/
theorem omvsa_pack_unpack (i : Fin omvsaDim) :
    (i.val / omvsaWordBits) * omvsaWordBits + i.val % omvsaWordBits = i.val := by
  have h := Nat.div_add_mod i.val omvsaWordBits
  rw [Nat.mul_comm]
  exact h

theorem omvsa_word_bound (i : Fin omvsaDim) : i.val / omvsaWordBits < omvsaWords := by
  have h : i.val < omvsaWords * omvsaWordBits := i.isLt
  exact Nat.div_lt_of_lt_mul (by rw [Nat.mul_comm]; exact h)

/-- A binary hypervector of dimension `d` represented as `Fin d → Bool`. -/
abbrev Hv (d : Nat) := Fin d → Bool

/-- Canonical zero hypervector. -/
def zeroHv (d : Nat) : Hv d := fun _ => false

/-- Component-wise XOR binding over `d` bits. -/
def bind {d : Nat} (a b : Hv d) : Hv d := fun i => xor (a i) (b i)

theorem bind_comm {d : Nat} (a b : Hv d) : bind a b = bind b a := by
  funext i
  exact Bool.xor_comm (a i) (b i)

theorem bind_assoc {d : Nat} (a b c : Hv d) :
    bind (bind a b) c = bind a (bind b c) := by
  funext i
  exact Bool.xor_assoc (a i) (b i) (c i)

theorem bind_zero {d : Nat} (a : Hv d) : bind a (zeroHv d) = a := by
  funext i
  simp [bind, zeroHv]

theorem bind_self {d : Nat} (a : Hv d) : bind a a = zeroHv d := by
  funext i
  simp [bind, zeroHv]

/-- Self-inverse binding identity: `bind (bind key val) key = val`. -/
theorem bind_self_inverse {d : Nat} (key val : Hv d) :
    bind (bind key val) key = val := by
  funext i
  simp only [bind]
  cases key i <;> cases val i <;> rfl

/-- Left-cancel self-inverse identity: `bind key (bind key val) = val`. -/
theorem bind_left_inverse {d : Nat} (key val : Hv d) :
    bind key (bind key val) = val := by
  rw [bind_comm key (bind key val)]
  exact bind_self_inverse key val

/-- Exact 10,240-bit instantiation of self-inverse XOR binding. -/
theorem omvsa_bind_self_inverse (key val : Hv omvsaDim) :
    bind (bind key val) key = val :=
  bind_self_inverse key val

/-- Recursive sum over prefix `[0 .. n)` of `Fin d`. -/
def countRange (n d : Nat) (hn : n ≤ d) (p : Fin d → Bool) : Nat :=
  match n with
  | 0 => 0
  | k + 1 =>
      let rest := countRange k d (Nat.le_of_succ_le hn) p
      let bit := if p ⟨k, Nat.lt_of_lt_of_le (Nat.lt_succ_self k) hn⟩ then 1 else 0
      rest + bit

/-- Total Hamming weight (popcount) of predicate `p : Fin d → Bool`. -/
def popcount (d : Nat) (p : Fin d → Bool) : Nat :=
  countRange d d (Nat.le_refl d) p

/-- Hamming distance between `a, b : Hv d`. -/
def hamming {d : Nat} (a b : Hv d) : Nat :=
  popcount d (fun i => xor (a i) (b i))

private theorem countRange_le (n d : Nat) (hn : n ≤ d) (p : Fin d → Bool) :
    countRange n d hn p ≤ n := by
  induction n with
  | zero => exact Nat.le_refl 0
  | succ k ih =>
      unfold countRange
      have hk := ih (Nat.le_of_succ_le hn)
      by_cases hpk : p ⟨k, Nat.lt_of_lt_of_le (Nat.lt_succ_self k) hn⟩
      · simp [hpk]; omega
      · simp [hpk]; omega

theorem hamming_le_dim {d : Nat} (a b : Hv d) : hamming a b ≤ d :=
  countRange_le d d (Nat.le_refl d) _

theorem hamming_nonneg {d : Nat} (a b : Hv d) : 0 ≤ hamming a b :=
  Nat.zero_le _

private theorem countRange_congr (n d : Nat) (hn : n ≤ d) (p q : Fin d → Bool)
    (heq : ∀ i : Fin d, p i = q i) :
    countRange n d hn p = countRange n d hn q := by
  induction n with
  | zero => rfl
  | succ k ih =>
      unfold countRange
      rw [ih (Nat.le_of_succ_le hn), heq ⟨k, Nat.lt_of_lt_of_le (Nat.lt_succ_self k) hn⟩]

theorem hamming_symm {d : Nat} (a b : Hv d) : hamming a b = hamming b a := by
  apply countRange_congr
  intro i
  exact Bool.xor_comm (a i) (b i)

private theorem countRange_eq_zero_iff (n d : Nat) (hn : n ≤ d) (p : Fin d → Bool) :
    countRange n d hn p = 0 ↔ ∀ i : Fin d, i.val < n → p i = false := by
  induction n with
  | zero =>
      constructor
      · intro _ i hi
        exact absurd hi (Nat.not_lt_zero _)
      · intro _
        rfl
  | succ k ih =>
      unfold countRange
      have hk_lt : k < d := Nat.lt_of_lt_of_le (Nat.lt_succ_self k) hn
      have ih_k := ih (Nat.le_of_succ_le hn)
      constructor
      · intro hsum i hi
        change countRange k d (Nat.le_of_succ_le hn) p +
            (if p ⟨k, hk_lt⟩ then 1 else 0) = 0 at hsum
        have hbit : (if p ⟨k, hk_lt⟩ then 1 else 0) = 0 := Nat.eq_zero_of_add_eq_zero_left hsum
        have hrest : countRange k d (Nat.le_of_succ_le hn) p = 0 := Nat.eq_zero_of_add_eq_zero_right hsum
        have hpk : p ⟨k, hk_lt⟩ = false := by
          cases hpv : p ⟨k, hk_lt⟩
          · rfl
          · simp [hpv] at hbit
        rcases Nat.lt_or_eq_of_le (Nat.le_of_lt_succ hi) with hlt | heq
        · exact ih_k.mp hrest i hlt
        · have : i = ⟨k, hk_lt⟩ := Fin.ext heq
          rw [this]
          exact hpk
      · intro hall
        have hrest : countRange k d (Nat.le_of_succ_le hn) p = 0 :=
          ih_k.mpr (fun i hi => hall i (Nat.lt_succ_of_lt hi))
        have hpk : p ⟨k, hk_lt⟩ = false := hall ⟨k, hk_lt⟩ (Nat.lt_succ_self k)
        simp [hrest, hpk]

theorem hamming_eq_zero_iff {d : Nat} (a b : Hv d) : hamming a b = 0 ↔ a = b := by
  rw [hamming, popcount, countRange_eq_zero_iff]
  constructor
  · intro h
    funext i
    have hi := h i i.isLt
    cases ha : a i <;> cases hb : b i <;> simp [ha, hb] at hi <;> rfl
  · intro heq i _
    subst heq
    simp

private theorem countRange_triangle (n d : Nat) (hn : n ≤ d) (a b c : Hv d) :
    countRange n d hn (fun i => xor (a i) (c i)) ≤
      countRange n d hn (fun i => xor (a i) (b i)) +
      countRange n d hn (fun i => xor (b i) (c i)) := by
  induction n with
  | zero => exact Nat.le_refl 0
  | succ k ih =>
      unfold countRange
      have hk_prev := ih (Nat.le_of_succ_le hn)
      let idx : Fin d := ⟨k, Nat.lt_of_lt_of_le (Nat.lt_succ_self k) hn⟩
      cases ha : a idx <;> cases hb : b idx <;> cases hc : c idx <;> simp <;> omega

theorem hamming_triangle {d : Nat} (a b c : Hv d) :
    hamming a c ≤ hamming a b + hamming b c :=
  countRange_triangle d d (Nat.le_refl d) a b c

theorem hamming_bind_isometry {d : Nat} (k a b : Hv d) :
    hamming (bind k a) (bind k b) = hamming a b := by
  apply countRange_congr
  intro i
  simp only [bind]
  cases k i <;> cases a i <;> cases b i <;> rfl

/-- Cyclic coordinate permutation over `d` bits: output bit `(i + shift) % d` equals input bit `i`,
    equivalently unpermute evaluates input at `(i + d - (shift % d)) % d`? Here we define:
    `permute v s i = v ((i + (d - s % d)) % d)` and `unpermute w s i = w ((i + s % d) % d)`.
    (So bit `j` in `v` moves forward to `(j + s) % d` in `permute v s`, matching `vsa_core.om`!) -/
def permute {d : Nat} (v : Hv d) (s : Nat) : Hv d :=
  fun i => v ⟨(i.val + (d - s % d)) % d, Nat.mod_lt _ (Nat.lt_of_le_of_lt (Nat.zero_le _) i.isLt)⟩

def unpermute {d : Nat} (w : Hv d) (s : Nat) : Hv d :=
  fun i => w ⟨(i.val + s % d) % d, Nat.mod_lt _ (Nat.lt_of_le_of_lt (Nat.zero_le _) i.isLt)⟩

private theorem perm_add_sub_mod {d : Nat} (hd : 0 < d) (i s : Nat) (hi : i < d) :
    ((i + s % d) % d + (d - s % d)) % d = i := by
  have hs : s % d < d := Nat.mod_lt s hd
  have hle : s % d ≤ d := Nat.le_of_lt hs
  rw [Nat.mod_add_mod]
  have h_reassoc : i + s % d + (d - s % d) = i + d := by omega
  rw [h_reassoc, Nat.add_mod_right]
  exact Nat.mod_eq_of_lt hi

private theorem perm_sub_add_mod {d : Nat} (hd : 0 < d) (i s : Nat) (hi : i < d) :
    ((i + (d - s % d)) % d + s % d) % d = i := by
  have hs : s % d < d := Nat.mod_lt s hd
  have hle : s % d ≤ d := Nat.le_of_lt hs
  rw [Nat.mod_add_mod]
  have h_reassoc : i + (d - s % d) + s % d = i + d := by omega
  rw [h_reassoc, Nat.add_mod_right]
  exact Nat.mod_eq_of_lt hi

theorem unpermute_permute {d : Nat} (v : Hv d) (s : Nat) :
    unpermute (permute v s) s = v := by
  funext i
  have hd : 0 < d := Nat.lt_of_le_of_lt (Nat.zero_le _) i.isLt
  simp only [unpermute, permute]
  congr 1
  exact Fin.ext (perm_add_sub_mod hd i.val s i.isLt)

theorem permute_unpermute {d : Nat} (w : Hv d) (s : Nat) :
    permute (unpermute w s) s = w := by
  funext i
  have hd : 0 < d := Nat.lt_of_le_of_lt (Nat.zero_le _) i.isLt
  simp only [permute, unpermute]
  congr 1
  exact Fin.ext (perm_sub_add_mod hd i.val s i.isLt)

theorem permute_injective {d : Nat} (s : Nat) :
    Function.Injective (fun v : Hv d => permute v s) := by
  intro a b hab
  have h := congrArg (fun x => unpermute x s) hab
  rw [unpermute_permute, unpermute_permute] at h
  exact h

theorem permute_surjective {d : Nat} (s : Nat) :
    Function.Surjective (fun v : Hv d => permute v s) := by
  intro y
  exact ⟨unpermute y s, permute_unpermute y s⟩

/-- Coordinate-wise majority count for `k` vectors `Fin k → Hv d`. -/
def onesAt {k d : Nat} (vecs : Fin k → Hv d) (i : Fin d) : Nat :=
  countRange k k (Nat.le_refl k) (fun j => vecs j i)

def zerosAt {k d : Nat} (vecs : Fin k → Hv d) (i : Fin d) : Nat :=
  countRange k k (Nat.le_refl k) (fun j => !vecs j i)

private theorem countRange_bool_partition (n k : Nat) (hn : n ≤ k) (f : Fin k → Bool) :
    countRange n k hn f + countRange n k hn (fun j => !f j) = n := by
  induction n with
  | zero => exact rfl
  | succ m ih =>
      unfold countRange
      have hm := ih (Nat.le_of_succ_le hn)
      cases f ⟨m, Nat.lt_of_lt_of_le (Nat.lt_succ_self m) hn⟩ <;> simp <;> omega

theorem ones_add_zeros {k d : Nat} (vecs : Fin k → Hv d) (i : Fin d) :
    onesAt vecs i + zerosAt vecs i = k :=
  countRange_bool_partition k k (Nat.le_refl k) (fun j => vecs j i)

/-- Coordinate-wise majority bundle with deterministic parity tie-breaker (`i.val % 2 == 1`). -/
def bundle {k d : Nat} (vecs : Fin k → Hv d) : Hv d :=
  fun i =>
    let ones := onesAt vecs i
    if 2 * ones > k then true
    else if 2 * ones = k then (i.val % 2 == 1)
    else false

/-- Coordinate-wise majority recoverability:
    whenever strictly fewer than half of the `k` bundled vectors disagree with bit `targetBit`
    at coordinate `i`, the bundled bit at `i` equals `targetBit` regardless of tie-breaker. -/
theorem bundle_coord_majority {k d : Nat} (vecs : Fin k → Hv d) (i : Fin d) (targetBit : Bool)
    (h_maj : 2 * countRange k k (Nat.le_refl k) (fun j => xor (vecs j i) targetBit) < k) :
    bundle vecs i = targetBit := by
  have hpart := ones_add_zeros vecs i
  unfold bundle
  cases targetBit
  · -- targetBit = false: disagree predicate is `(vecs j i) != false` = `vecs j i`, i.e., `onesAt`
    have heq : countRange k k (Nat.le_refl k) (fun j => xor (vecs j i) false) = onesAt vecs i := by
      apply countRange_congr
      intro j
      cases vecs j i <;> rfl
    rw [heq] at h_maj
    have h_not_gt : ¬ (2 * onesAt vecs i > k) := by omega
    have h_not_eq : ¬ (2 * onesAt vecs i = k) := by omega
    simp [h_not_gt, h_not_eq]
  · -- targetBit = true: disagree predicate is `(vecs j i) != true` = `!vecs j i`, i.e., `zerosAt`
    have heq : countRange k k (Nat.le_refl k) (fun j => xor (vecs j i) true) = zerosAt vecs i := by
      apply countRange_congr
      intro j
      cases vecs j i <;> rfl
    rw [heq] at h_maj
    have h_gt : 2 * onesAt vecs i > k := by omega
    simp [h_gt]

/-- Unanimous consensus corollary for non-empty bundles (`k > 0`). -/
theorem bundle_unanimous {k d : Nat} (hk : 0 < k) (vecs : Fin k → Hv d) (i : Fin d) (b : Bool)
    (hall : ∀ j : Fin k, vecs j i = b) :
    bundle vecs i = b := by
  apply bundle_coord_majority
  have hzero : countRange k k (Nat.le_refl k) (fun j => xor (vecs j i) b) = 0 := by
    rw [countRange_eq_zero_iff]
    intro j _
    rw [hall j]
    cases b <;> rfl
  rw [hzero]
  exact hk

/-- Global Associative Recall Soundness Theorem (triangle inequality margin):
    If `probe` agrees with true target `target` within total superposition + channel noise `η + ε`
    (`hamming probe target ≤ η + ε`), and every distractor `other` is separated from `target`
    by more than twice the noise radius (`2 * (η + ε) < hamming target other`), then
    nearest-neighbor Hamming search strictly prefers `target` over `other`. -/
theorem associative_recall_soundness {d : Nat} (probe target other : Hv d)
    (eta eps : Nat)
    (h_noise : hamming probe target ≤ eta + eps)
    (h_sep : 2 * (eta + eps) < hamming target other) :
    hamming probe target < hamming probe other := by
  have h_tri := hamming_triangle target probe other
  rw [hamming_symm target probe] at h_tri
  omega

/-- End-to-end bound-unbinding associative recall soundness:
    Unbinding noisy superposition `supNoisy` with `key` and comparing against codebook
    entries preserves exact distance separation when `supNoisy` is within `eta + eps` of `bind key target`. -/
theorem bound_unbind_recall_soundness {d : Nat} (key supNoisy target other : Hv d)
    (eta eps : Nat)
    (h_sup : hamming supNoisy (bind key target) ≤ eta + eps)
    (h_sep : 2 * (eta + eps) < hamming target other) :
    hamming (bind supNoisy key) target < hamming (bind supNoisy key) other := by
  have h_probe_target : hamming (bind supNoisy key) target ≤ eta + eps := by
    have h_iso := hamming_bind_isometry key supNoisy (bind key target)
    rw [bind_left_inverse key target, bind_comm key supNoisy] at h_iso
    omega
  exact associative_recall_soundness (bind supNoisy key) target other eta eps h_probe_target h_sep

/-- Concrete decidable positive & negative sanity controls for `d = 8`. -/
private def exA : Hv 8 := fun i => i.val % 2 == 0
private def exB : Hv 8 := fun i => i.val < 4

theorem ex_bind_self_inv : bind (bind exA exB) exA = exB :=
  bind_self_inverse exA exB

theorem ex_perm_roundtrip : unpermute (permute exA 3) 3 = exA :=
  unpermute_permute exA 3

theorem ex_perm_noncomm : hamming (permute exB 1) exB > 0 := by
  decide

#print axioms omvsa_dim_eq
#print axioms omvsa_pack_unpack
#print axioms omvsa_word_bound
#print axioms bind_comm
#print axioms bind_assoc
#print axioms bind_self_inverse
#print axioms omvsa_bind_self_inverse
#print axioms hamming_nonneg
#print axioms hamming_le_dim
#print axioms hamming_symm
#print axioms hamming_eq_zero_iff
#print axioms hamming_triangle
#print axioms hamming_bind_isometry
#print axioms unpermute_permute
#print axioms permute_unpermute
#print axioms permute_injective
#print axioms permute_surjective
#print axioms bundle_coord_majority
#print axioms bundle_unanimous
#print axioms associative_recall_soundness
#print axioms bound_unbind_recall_soundness
#print axioms ex_perm_noncomm

end OmegaVsa
