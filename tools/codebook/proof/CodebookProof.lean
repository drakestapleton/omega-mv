/-
SPDX-License-Identifier: AGPL-3.0-only
T-002 items 7-10: the signed layered digit codebook (model of tools/codebook/codebook.om).
Checked with Lean 4.35.0, core only (no Mathlib), no proof holes.

Wire form: a message is a list of codes; a code is a list of 3-digit groups (each < 1000) where
every group but the last is an escape 900..999 and the last is a terminal 000..899.
The digit string is the concatenation of the groups, each written as exactly 3 decimal digits.
`lean --run CodebookProof.lean gen|exh|dec` prints the differential-test vectors.
-/
set_option linter.deprecated false
set_option linter.unusedSimpArgs false

namespace Codebook

/-- one 3-digit group, most significant digit first -/
def tri (n : Nat) : List Nat := [n / 100 % 10, n / 10 % 10, n % 10]

/-- a well-formed layered code: (9xx)^k then one terminal 000..899 -/
inductive Valid : List Nat → Prop
  | term {g : Nat} : g < 900 → Valid [g]
  | esc {g : Nat} {t : List Nat} : 900 ≤ g → g < 1000 → Valid t → Valid (g :: t)

def encC (c : List Nat) : List Nat := c.flatMap tri
def encode (m : List (List Nat)) : List Nat := m.flatMap encC

/-- digits to 3-digit groups; none on a non-digit or a length that is not a multiple of 3 -/
def groups : List Nat → Option (List Nat)
  | [] => some []
  | a :: b :: c :: r =>
    if a < 10 ∧ b < 10 ∧ c < 10 then (groups r).map (fun gs => (a * 100 + b * 10 + c) :: gs) else none
  | _ => none

/-- groups to codes; `acc` holds the escapes read so far; a dangling escape is none -/
def parse : List Nat → List Nat → Option (List (List Nat))
  | [], [] => some []
  | [], _ :: _ => none
  | g :: gs, acc =>
    if 900 ≤ g then parse gs (acc ++ [g]) else (parse gs []).map (fun r => (acc ++ [g]) :: r)

def decode (ds : List Nat) : Option (List (List Nat)) := (groups ds).bind (fun gs => parse gs [])

theorem Valid.lt {c : List Nat} (h : Valid c) : ∀ g ∈ c, g < 1000 := by
  induction h with
  | term hg => intro x hx; simp at hx; omega
  | esc h1 h2 _ ih =>
    intro x hx; simp at hx
    rcases hx with hx | hx
    · omega
    · exact ih x hx

theorem groups_tri (n : Nat) (r : List Nat) (h : n < 1000) :
    groups (tri n ++ r) = (groups r).map (n :: ·) := by
  have e : n / 100 % 10 * 100 + n / 10 % 10 * 10 + n % 10 = n := by omega
  simp only [tri, List.cons_append, List.nil_append, groups]
  rw [if_pos (by omega), e]

theorem groups_encC (c r : List Nat) (h : ∀ g ∈ c, g < 1000) :
    groups (encC c ++ r) = (groups r).map (c ++ ·) := by
  induction c with
  | nil => simp [encC]
  | cons g t ih =>
    have hg : g < 1000 := h g (by simp)
    have ht : ∀ x ∈ t, x < 1000 := fun x hx => h x (by simp [hx])
    simp only [encC, List.flatMap_cons, List.append_assoc] at ih ⊢
    rw [groups_tri g _ hg, ih ht, Option.map_map]
    rfl

theorem groups_encode (m : List (List Nat)) (h : ∀ c ∈ m, Valid c) :
    groups (encode m) = some m.flatten := by
  induction m with
  | nil => simp [encode, groups]
  | cons c t ih =>
    have hc : Valid c := h c (by simp)
    have ht : ∀ x ∈ t, Valid x := fun x hx => h x (by simp [hx])
    have e : encode (c :: t) = encC c ++ encode t := by simp [encode, encC]
    rw [e, groups_encC c _ hc.lt, ih ht]
    simp

theorem parse_valid {c : List Nat} (h : Valid c) (rest acc : List Nat) :
    parse (c ++ rest) acc = (parse rest []).map ((acc ++ c) :: ·) := by
  induction h generalizing acc with
  | term hg =>
    simp only [List.cons_append, List.nil_append, parse]
    rw [if_neg (by omega)]
  | esc h1 _ _ ih =>
    simp only [List.cons_append, parse]
    rw [if_pos h1, ih]
    simp

theorem parse_flatten (m : List (List Nat)) (h : ∀ c ∈ m, Valid c) :
    parse m.flatten [] = some m := by
  induction m with
  | nil => simp [parse]
  | cons c t ih =>
    have hc : Valid c := h c (by simp)
    have ht : ∀ x ∈ t, Valid x := fun x hx => h x (by simp [hx])
    simp only [List.flatten_cons]
    rw [parse_valid hc, ih ht]
    simp

/-- Round trip: every layered message decodes back to itself. -/
theorem decode_encode (m : List (List Nat)) (h : ∀ c ∈ m, Valid c) :
    decode (encode m) = some m := by
  simp [decode, groups_encode m h, parse_flatten m h]

/-- Unique decodability: two messages with the same digits are the same message. -/
theorem encode_injective (m1 m2 : List (List Nat)) (h1 : ∀ c ∈ m1, Valid c)
    (h2 : ∀ c ∈ m2, Valid c) (e : encode m1 = encode m2) : m1 = m2 := by
  have a := decode_encode m1 h1
  rw [e, decode_encode m2 h2] at a
  exact (Option.some.inj a).symm

/-- Prefix-freeness: no codeword's digits are a prefix of another codeword's digits. -/
theorem prefix_free {c1 c2 : List Nat} (h1 : Valid c1) (h2 : Valid c2) (r : List Nat)
    (e : encC c1 ++ r = encC c2) : c1 = c2 ∧ r = [] := by
  induction h1 generalizing c2 with
  | @term g1 hg1 =>
    cases h2 with
    | @term g2 hg2 =>
      simp [encC, tri] at e
      obtain ⟨a, b, c, d⟩ := e
      exact ⟨by simp; omega, d⟩
    | @esc g2 t2 hg2 hg2' _ =>
      simp [encC, tri] at e
      obtain ⟨a, b, c, _⟩ := e
      omega
  | @esc g1 t1 hg1 hg1' _ ih =>
    cases h2 with
    | @term g2 hg2 =>
      simp [encC, tri] at e
      obtain ⟨a, b, c, _⟩ := e
      omega
    | @esc g2 t2 hg2 hg2' v2 =>
      simp only [encC, List.flatMap_cons, tri, List.cons_append, List.nil_append,
        List.append_assoc, List.cons.injEq] at e
      obtain ⟨a, b, c, d⟩ := e
      have hg : g1 = g2 := by omega
      have := ih v2 d
      exact ⟨by rw [hg, this.1], this.2⟩

theorem prefix_free' {c1 c2 : List Nat} (h1 : Valid c1) (h2 : Valid c2) (hne : c1 ≠ c2) :
    ¬ (encC c1 <+: encC c2) := by
  rintro ⟨r, e⟩
  exact hne (prefix_free h1 h2 r e).1

/-! Codebook: an append-only TSV `code<TAB>type<TAB>meaning`; first match wins. -/

structure Entry where
  code : List Nat
  ty : String
  meaning : String
  deriving DecidableEq, Repr

def lookup (cb : List Entry) (c : List Nat) : Option Entry := cb.find? (fun e => e.code == c)

def lookAll (cb : List Entry) : List (List Nat) → Option (List Entry)
  | [] => some []
  | c :: cs => (lookup cb c).bind (fun e => (lookAll cb cs).map (e :: ·))

def decodeSem (cb : List Entry) (ds : List Nat) : Option (List Entry) :=
  (decode ds).bind (lookAll cb)

theorem lookup_append (cb ext : List Entry) (c : List Nat) (e : Entry)
    (h : lookup cb c = some e) : lookup (cb ++ ext) c = some e := by
  simp only [lookup, List.find?_append] at h ⊢
  rw [h]; rfl

theorem lookAll_append (cb ext : List Entry) (cs : List (List Nat)) (r : List Entry)
    (h : lookAll cb cs = some r) : lookAll (cb ++ ext) cs = some r := by
  induction cs generalizing r with
  | nil => simpa [lookAll] using h
  | cons c t ih =>
    simp only [lookAll] at h ⊢
    cases hl : lookup cb c with
    | none => rw [hl] at h; simp at h
    | some e =>
      rw [hl] at h
      rw [lookup_append cb ext c e hl]
      cases ht : lookAll cb t with
      | none => rw [ht] at h; simp at h
      | some r' =>
        rw [ht] at h
        rw [ih r' ht]
        exact h

/-- Append-only extension never changes a message that already decoded. -/
theorem append_preserves (cb ext : List Entry) (ds : List Nat) (r : List Entry)
    (h : decodeSem cb ds = some r) : decodeSem (cb ++ ext) ds = some r := by
  unfold decodeSem at h ⊢
  cases hd : decode ds with
  | none => rw [hd] at h; simp at h
  | some cs =>
    rw [hd] at h
    exact lookAll_append cb ext cs r h

/-! Verification and demotion, in the order codebook.om checks them. -/

inductive Status | ok | unsigned | badsender | badfmt | badcb | baddecode | unknown | badmac | stale
  deriving DecidableEq, Repr

structure Line where
  signed : Bool      -- an ocb2 field with a non-empty MAC
  senderOk : Bool
  fmtOk : Bool
  cbOk : Bool        -- the line's codebook sha equals the loaded codebook's sha
  decOk : Bool
  known : Bool
  macOk : Bool       -- HMAC-SHA256(key, ocb2|cbsha|counter|lane|ts|from|to|tag|text|ref|digits) equals the line's MAC
  counter : Nat
  last : Nat         -- the sender's last accepted counter

def status (l : Line) : Status :=
  if !l.signed then .unsigned
  else if !l.senderOk then .badsender
  else if !l.fmtOk then .badfmt
  else if !l.cbOk then .badcb
  else if !l.decOk then .baddecode
  else if !l.known then .unknown
  else if !l.macOk then .badmac
  else if l.counter ≤ l.last then .stale
  else .ok

/-- a code is an emergency when it is the single group 300..399 -/
def emerg (c : List Nat) : Bool :=
  match c with
  | [g] => 300 ≤ g && g < 400
  | _ => false

/-- the trit a line produces: 2 only for a verified line carrying an emergency code -/
def lineTrit (st : Status) (cs : List (List Nat)) : Nat :=
  if st = .ok ∧ cs.any emerg = true then 2 else 1

theorem lineTrit_le (st : Status) (cs : List (List Nat)) : lineTrit st cs = 1 ∨ lineTrit st cs = 2 := by
  unfold lineTrit; split <;> simp

/-- Demotion: an unverified line never yields 2. -/
theorem unverified_never_two (st : Status) (cs : List (List Nat)) (h : st ≠ .ok) :
    lineTrit st cs ≠ 2 := by
  unfold lineTrit; simp [h]

theorem two_iff (st : Status) (cs : List (List Nat)) :
    lineTrit st cs = 2 ↔ st = .ok ∧ cs.any emerg = true := by
  unfold lineTrit; split <;> simp_all

theorem unsigned_demoted (l : Line) (cs) (h : l.signed = false) : lineTrit (status l) cs = 1 := by
  simp [lineTrit, status, h]

theorem stale_demoted (l : Line) (cs) (h : l.counter ≤ l.last) : lineTrit (status l) cs ≠ 2 := by
  apply unverified_never_two
  simp only [status]
  split <;> (try simp) <;> split <;> (try simp) <;> split <;> (try simp) <;> split <;> (try simp) <;>
    split <;> (try simp) <;> split <;> (try simp) <;> split <;> (try simp) <;> split <;> (try simp) <;> omega

theorem badmac_demoted (l : Line) (cs) (h : l.macOk = false) : lineTrit (status l) cs ≠ 2 := by
  apply unverified_never_two
  simp only [status, h]
  split <;> (try simp) <;> split <;> (try simp) <;> split <;> (try simp) <;> split <;> (try simp) <;>
    split <;> (try simp) <;> split <;> simp

/-! Test-vector generator: the same `encode` the theorems are about. -/

def showCode (c : List Nat) : String := ".".intercalate (c.map toString)
def showMsg (m : List (List Nat)) : String := " ".intercalate (m.map showCode)
def showDigits (ds : List Nat) : String := String.join (ds.map toString)
def showDec : Option (List (List Nat)) → String
  | some m => showMsg m
  | none => "ERR"

def lcg (s : Nat) : Nat := (s * 6364136223846793005 + 1442695040888963407) % 18446744073709551616
def rnd (s : Nat) : Nat := s / 4294967296

/-- a random valid code: k escapes (0..3) then a terminal -/
def genCode (s : Nat) : List Nat × Nat :=
  let s1 := lcg s
  let k := rnd s1 % 4
  let rec go : Nat → Nat → List Nat × Nat
    | 0, s => let s' := lcg s; ([rnd s' % 900], s')
    | n + 1, s => let s' := lcg s; let (t, s'') := go n s'; ((900 + rnd s' % 100) :: t, s'')
  go k s1

def genMsg (s : Nat) : List (List Nat) × Nat :=
  let s1 := lcg s
  let n := rnd s1 % 7
  let rec go : Nat → Nat → List (List Nat) × Nat
    | 0, s => ([], s)
    | n + 1, s => let (c, s') := genCode s; let (t, s'') := go n s'; (c :: t, s'')
  go n s1

def genDigits (s : Nat) : List Nat × Nat :=
  let s1 := lcg s
  let n := 3 * (rnd s1 % 6) + (if rnd s1 / 8 % 8 = 0 then 1 else 0)
  let rec go : Nat → Nat → List Nat × Nat
    | 0, s => ([], s)
    | n + 1, s =>
      let s' := lcg s
      let r := rnd s' % 20
      let d := if r < 10 then 9 else r - 10
      let (t, s'') := go n s'
      (d :: t, s'')
  go n s1

partial def loopGen (i : Nat) (s : Nat) (acc : Array String) : Array String :=
  if i = 0 then acc else
  let (m, s') := genMsg s
  let row :=
    let left := showMsg m
    let right := showDigits (encode m)
    if left == "" && right == "" then "" else s!"{left}	{right}"
  loopGen (i - 1) s' (acc.push row)

partial def loopDec (i : Nat) (s : Nat) (acc : Array String) : Array String :=
  if i = 0 then acc else
  let (ds, s') := genDigits s
  let row :=
    let left := showDigits ds
    let right := showDec (decode ds)
    if left == "" && right == "" then "" else s!"{left}	{right}"
  loopDec (i - 1) s' (acc.push row)

def main (args : List String) : IO Unit := do
  match args with
  | ["gen", n] =>
    for l in loopGen n.toNat! 20261115 #[] do IO.println l
  | ["dec", n] =>
    for l in loopDec n.toNat! 777 #[] do IO.println l
  | ["exh"] =>
    for t in List.range 900 do
      IO.println s!"{showMsg [[t]]}\t{showDigits (encode [[t]])}"
    for e in List.range 100 do
      for t in List.range 900 do
        let m := [[900 + e, t]]
        IO.println s!"{showMsg m}\t{showDigits (encode m)}"
  | _ => IO.eprintln "usage: gen N | dec N | exh"

end Codebook

def main (args : List String) : IO Unit := Codebook.main args
