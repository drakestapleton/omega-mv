/-
  T-002 trit signal: the classifier of tools/trit/trit.om, proved in Lean 4 core.
  Part 1 (TritSignal) is the abstract lane/cursor model; part 2 (TritBin, at the end) mirrors trit.om
  function by function and is run against trit.bin by difftest.sh.
  (no Mathlib; every theorem closed, axioms printed below).
  Check: lean TritSignal.lean   (exit 0, no output besides the `#print axioms` lines)

  Model. A lane's unread complete content lines are a list; each line has an `isStop` flag.
  `classify` is the normal-lane trit. `St` holds the pending admitted emergency lines and the
  unread normal lines; `stepE` applies one arrival or one ack, as `trit DIR --ack BOT` does.
-/
namespace TritSignal

inductive Trit where
  | zero | one | two
  deriving DecidableEq, Repr

def Trit.rank : Trit → Nat
  | .zero => 0
  | .one => 1
  | .two => 2

/-- The program's `tmax`: keep `a` when it ranks at least as high as `b`. -/
def Trit.max (a b : Trit) : Trit := if b.rank ≤ a.rank then a else b

theorem rank_lt_three (t : Trit) : t.rank < 3 := by cases t <;> decide
theorem rank_inj (a b : Trit) : a.rank = b.rank → a = b := by cases a <;> cases b <;> decide
theorem max_zero (t : Trit) : t.max .zero = t := by cases t <;> rfl
theorem zero_max (t : Trit) : Trit.zero.max t = t := by cases t <;> rfl
theorem max_two (t : Trit) : t.max .two = .two := by cases t <;> rfl
theorem two_max (t : Trit) : Trit.two.max t = .two := by cases t <;> rfl
theorem max_assoc (a b c : Trit) : (a.max b).max c = a.max (b.max c) := by
  cases a <;> cases b <;> cases c <;> rfl
theorem max_comm (a b : Trit) : a.max b = b.max a := by cases a <;> cases b <;> rfl
theorem rank_max (a b : Trit) : (a.max b).rank = Nat.max a.rank b.rank := by
  cases a <;> cases b <;> rfl

structure Line where
  isStop : Bool
  deriving DecidableEq

theorem max_eq_two (a b : Trit) : a.max b = .two ↔ a = .two ∨ b = .two := by
  cases a <;> cases b <;> decide
theorem max_eq_zero (a b : Trit) : a.max b = .zero ↔ a = .zero ∧ b = .zero := by
  cases a <;> cases b <;> decide

/-- The trit one line contributes on its own. -/
def lineTrit (l : Line) : Trit := if l.isStop then .two else .one

/-- The normal-lane classifier: the maximum of the line trits, 0 for no lines. -/
def classify : List Line → Trit
  | [] => .zero
  | l :: ls => (lineTrit l).max (classify ls)

/-- Totality: `classify` is a structurally recursive (so total) function into exactly three
    values. -/
theorem classify_total (ls : List Line) :
    classify ls = .zero ∨ classify ls = .one ∨ classify ls = .two := by
  cases classify ls <;> simp

theorem classify_two_iff (ls : List Line) :
    classify ls = .two ↔ ∃ l ∈ ls, l.isStop = true := by
  induction ls with
  | nil => simp [classify]
  | cons l ls ih =>
    cases h : l.isStop <;> simp [classify, lineTrit, h, max_eq_two, ih]

theorem classify_zero_iff (ls : List Line) : classify ls = .zero ↔ ls = [] := by
  cases ls with
  | nil => simp [classify]
  | cons l t => cases h : l.isStop <;> simp [classify, lineTrit, h, max_eq_zero]

/-- 2 dominates 1 dominates 0: the trit of two batches of lines is the maximum of their trits. -/
theorem classify_append (a b : List Line) :
    classify (a ++ b) = (classify a).max (classify b) := by
  induction a with
  | nil => simp [classify, zero_max]
  | cons l a ih => simp only [List.cons_append, classify, ih, max_assoc]

theorem classify_one_iff (ls : List Line) :
    classify ls = .one ↔ ls ≠ [] ∧ ∀ l ∈ ls, l.isStop = false := by
  have h2 := classify_two_iff ls
  have h0 := classify_zero_iff ls
  constructor
  · intro h
    refine ⟨(fun e => by rw [h0.2 e] at h; cases h), fun l hl => ?_⟩
    cases hs : l.isStop
    · rfl
    · have := h2.2 ⟨l, hl, hs⟩; rw [h] at this; cases this
  · intro hh
    obtain ⟨hne, hall⟩ := hh
    rcases classify_total ls with h | h | h
    · exact absurd (h0.1 h) hne
    · exact h
    · obtain ⟨l, hl, hs⟩ := h2.1 h; rw [hall l hl] at hs; cases hs

theorem stop_dominates (ls : List Line) (h : ∃ l ∈ ls, l.isStop = true) :
    classify ls = .two := (classify_two_iff ls).2 h

theorem unread_beats_zero (ls : List Line) (h : ls ≠ []) : classify ls ≠ .zero :=
  fun e => h ((classify_zero_iff ls).1 e)

theorem more_lines_never_lower (a b : List Line) :
    (classify a).rank ≤ (classify (a ++ b)).rank := by
  rw [classify_append, rank_max]; exact Nat.le_max_left _ _

/-- The program's loop (`scann`): a stop line gives 2 at once, any other line raises to 1. -/
def stepN (t : Trit) (l : Line) : Trit := if l.isStop then .two else t.max .one

theorem stepN_eq (t : Trit) (l : Line) : stepN t l = t.max (classify [l]) := by
  cases l with | mk s => cases s <;> cases t <;> rfl

theorem fold_eq_gen (ls : List Line) (t : Trit) :
    ls.foldl stepN t = t.max (classify ls) := by
  induction ls generalizing t with
  | nil => simp [classify, max_zero]
  | cons l ls ih =>
    rw [List.foldl_cons, ih, stepN_eq, max_assoc, ← classify_append]; rfl

theorem scan_correct (ls : List Line) : ls.foldl stepN .zero = classify ls := by
  rw [fold_eq_gen, zero_max]

/-! Lanes, cursors and token acks.

Each lane is an append-only list of complete content lines with a cursor `c` (lines read). The
emergency lane holds admitted lines only. A reader is told a token: the lane's length when it read.
`ack k` moves the cursor to `k` only when `c ≤ k ≤ length` (the program also checks that the line
before `k` hashes to the token, which in this append-only model always holds); otherwise it is
refused and nothing changes. -/

structure St where
  e : List Line
  ec : Nat
  n : List Line
  nc : Nat

/-- The program's `state`: a pending emergency gives 2 and the normal lane is not read. -/
def St.trit (s : St) : Trit := if s.ec < s.e.length then .two else classify (s.n.drop s.nc)

inductive Ev where
  | normal (l : Line)
  | emerg (l : Line)
  | ackN (k : Nat)
  | ackE (k : Nat)

def Ev.isAckE : Ev → Bool
  | .ackE _ => true
  | _ => false

def ackTo (c k len : Nat) : Nat := if c ≤ k ∧ k ≤ len then k else c

def stepE (s : St) : Ev → St
  | .normal l => { s with n := s.n ++ [l] }
  | .emerg l => { s with e := s.e ++ [l] }
  | .ackN k => { s with nc := ackTo s.nc k s.n.length }
  | .ackE k => { s with ec := ackTo s.ec k s.e.length }

def run (s : St) (es : List Ev) : St := es.foldl stepE s

theorem ackTo_ge (c k len : Nat) : c ≤ ackTo c k len := by
  unfold ackTo; split <;> omega

theorem ackTo_le (c k len : Nat) (h : c ≤ len) : ackTo c k len ≤ len := by
  unfold ackTo; split <;> omega

/-- Cursors never move backward: a stale token cannot un-read anything. -/
theorem cursors_monotone (s : St) (ev : Ev) :
    s.nc ≤ (stepE s ev).nc ∧ s.ec ≤ (stepE s ev).ec := by
  cases ev with
  | normal l => exact ⟨Nat.le_refl _, Nat.le_refl _⟩
  | emerg l => exact ⟨Nat.le_refl _, Nat.le_refl _⟩
  | ackN k => exact ⟨ackTo_ge _ _ _, Nat.le_refl _⟩
  | ackE k => exact ⟨Nat.le_refl _, ackTo_ge _ _ _⟩

/-- A refused ack (stale, behind the cursor, or past the end) changes nothing. -/
theorem refused_ack_unchanged (s : St) (k : Nat) (hk : k < s.nc ∨ s.n.length < k) :
    stepE s (.ackN k) = s := by
  have h : ¬ (s.nc ≤ k ∧ k ≤ s.n.length) := by omega
  simp [stepE, ackTo, h]

/-- The ack race: lines that arrive after the read stay unread after acking the read's token. -/
theorem ack_race (s : St) (ls : List Line) (hv : s.nc ≤ s.n.length) :
    ((stepE { s with n := s.n ++ ls } (.ackN s.n.length)).n).drop
      (stepE { s with n := s.n ++ ls } (.ackN s.n.length)).nc = ls := by
  have h : s.nc ≤ s.n.length ∧ s.n.length ≤ (s.n ++ ls).length := by
    simp only [List.length_append]; omega
  simp only [stepE, ackTo, h]
  exact List.drop_left ..

theorem pending_is_two (s : St) (h : s.ec < s.e.length) : s.trit = .two := by
  simp [St.trit, h]

theorem run_noE (s : St) (es : List Ev) (h : ∀ ev ∈ es, ev.isAckE = false) :
    (run s es).ec = s.ec ∧ s.e.length ≤ (run s es).e.length := by
  induction es generalizing s with
  | nil => exact ⟨rfl, Nat.le_refl _⟩
  | cons ev es ih =>
    have hr : ∀ x ∈ es, x.isAckE = false := fun x hx => h x (List.mem_cons_of_mem ev hx)
    have he := h ev (List.mem_cons_self ..)
    obtain ⟨h1, h2⟩ := ih (stepE s ev) hr
    show (run (stepE s ev) es).ec = s.ec ∧ s.e.length ≤ (run (stepE s ev) es).e.length
    cases ev with
    | normal l => exact ⟨h1, h2⟩
    | emerg l =>
      refine ⟨h1, Nat.le_trans ?_ h2⟩
      show s.e.length ≤ (s.e ++ [l]).length
      simp
    | ackN k => exact ⟨h1, h2⟩
    | ackE k => simp [Ev.isAckE] at he

theorem emerg_arrival (s : St) (es : List Ev) (hv : s.ec ≤ s.e.length)
    (h : ∀ ev ∈ es, ev.isAckE = false) (hm : ∃ l, Ev.emerg l ∈ es) :
    (run s es).ec < (run s es).e.length := by
  induction es generalizing s with
  | nil => obtain ⟨l, hl⟩ := hm; simp at hl
  | cons ev es ih =>
    have hr : ∀ x ∈ es, x.isAckE = false := fun x hx => h x (List.mem_cons_of_mem ev hx)
    have he := h ev (List.mem_cons_self ..)
    show (run (stepE s ev) es).ec < (run (stepE s ev) es).e.length
    have tail : (∃ l, Ev.emerg l ∈ es) → (stepE s ev).ec ≤ (stepE s ev).e.length →
        (run (stepE s ev) es).ec < (run (stepE s ev) es).e.length :=
      fun hm' hv' => ih (stepE s ev) hv' hr hm'
    cases ev with
    | emerg l =>
      obtain ⟨h1, h2⟩ := run_noE (stepE s (.emerg l)) es hr
      rw [h1]
      refine Nat.lt_of_lt_of_le ?_ h2
      show s.ec < (s.e ++ [l]).length
      simp; omega
    | normal l =>
      obtain ⟨l', hl'⟩ := hm
      have : Ev.emerg l' ∈ es := by
        cases hl' with
        | tail _ h2 => exact h2
      exact tail ⟨l', this⟩ hv
    | ackN k =>
      obtain ⟨l', hl'⟩ := hm
      have : Ev.emerg l' ∈ es := by
        cases hl' with
        | tail _ h2 => exact h2
      exact tail ⟨l', this⟩ hv
    | ackE k => simp [Ev.isAckE] at he

/-- Never starved: under any interleaving of normal arrivals, emergency arrivals and normal-lane
    acks, a pending emergency, or one that arrives at any point, is classified 2 until the
    emergency lane itself is acked. -/
theorem never_starved (s : St) (es : List Ev) (hv : s.ec ≤ s.e.length)
    (h : ∀ ev ∈ es, ev.isAckE = false)
    (hp : s.ec < s.e.length ∨ ∃ l, Ev.emerg l ∈ es) : (run s es).trit = .two := by
  apply pending_is_two
  cases hp with
  | inl h0 =>
    obtain ⟨h1, h2⟩ := run_noE s es h
    rw [h1]; exact Nat.lt_of_lt_of_le h0 h2
  | inr hm => exact emerg_arrival s es hv h hm

/-- Acking the emergency lane at its read token clears it; normal lines are then classified. -/
theorem emerg_ack_clears (s : St) (hv : s.ec ≤ s.e.length) :
    (stepE s (.ackE s.e.length)).trit = classify (s.n.drop s.nc) := by
  have h : s.ec ≤ s.e.length ∧ s.e.length ≤ s.e.length := ⟨hv, Nat.le_refl _⟩
  simp [stepE, ackTo, h, St.trit]

end TritSignal

/-! ## TritBin: the shipped classifier, line for line (tools/trit/trit.om)

Bytes are read as characters (the inbox files are ASCII). Each definition names the .om function
it mirrors. `proof/difftest.sh` runs this model (`#eval` in Diff.lean) and trit.bin on the same
generated fixture directories and requires identical stdout, stderr and exit status. The SHA-256
tables below are the seeded ones (seed/trace/sha256.om kinit/hinit), copied by difftest.sh. -/

namespace TritBin
open TritSignal

def isDig (c : Char) : Bool := '0' ≤ c && c ≤ '9'
/-- okch -/
def okch (c : Char) : Bool := isDig c || c == '-' || ('a' ≤ c && c ≤ 'z')

/-- lnend/the scan loops: complete lines (start offset, bytes without the newline); a trailing
    partial line is dropped. -/
def lines : Nat → List Char → Nat → List (Nat × List Char)
  | 0, _, _ => []
  | fuel + 1, s, pos =>
    match s.idxOf? '\n' with
    | none => []
    | some i => (pos, s.take i) :: lines fuel (s.drop (i + 1)) (pos + i + 1)

def linesOf (s : List Char) : List (Nat × List Char) := lines (s.length + 1) s 0

/-- ists -/
def ists (l : List Char) : Bool :=
  decide (11 ≤ l.length) && (List.range 11).all fun i =>
    let c := l.getD i ' '
    if i == 4 || i == 7 then c == '-' else if i == 10 then c == 'T' else isDig c

def fields (l : List Char) : List String := (String.ofList l).splitOn "|"

/-- lfmt: a last field starting "ocb2:" or leftover "ocb1:" is the codebook signature, not content;
    then the tag is field 3 in the 6-field format, else field 2. -/
def lfmt (l : List Char) : List String × Nat :=
  let fs := fields l
  let n := fs.length
  let last := fs.getD (n - 1) ""
  let fs' := if 2 ≤ n && (last.startsWith "ocb2:" || last.startsWith "ocb1:") then fs.take (n - 1) else fs
  (fs', if fs'.length == 6 then 3 else 2)

/-- stopx: exact STOP -/
def stopx (t : String) : Bool :=
  let c := t.toList
  c.take 4 == ['S', 'T', 'O', 'P'] && (c.length == 4 || c.getD 4 ' ' == ' ' || c.getD 4 ' ' == ':')

/-- lnkind: stop wins over fyi. -/
def lnkind (l : List Char) : Trit :=
  let (fs, tg) := lfmt l
  if fs[tg]? == some "stop" then .two
  else if (fs[tg + 1]?.map stopx).getD false then .two
  else if fs[tg]? == some "fyi" then .zero
  else .one

/-- okname -/
def okname (allow : List String) (s : String) : Bool :=
  decide (1 ≤ s.length) && decide (s.length ≤ 64) && s.toList.all okch &&
    (s == "drake" || allow.contains s)

def dig2 (l : List Char) (q : Nat) : Nat :=
  let a := l.getD q ' '
  let b := l.getD (q + 1) ' '
  if isDig a && isDig b then (a.toNat - 48) * 10 + (b.toNat - 48) else 100000

/-- days (civil to days, as in the .om) -/
def days (y m d : Nat) : Nat :=
  let yy := if m ≤ 2 then y - 1 else y
  let era := yy / 400
  let yoe := yy - era * 400
  let mp := if 2 < m then m - 3 else m + 9
  let doy := (153 * mp + 2) / 5 + (d - 1)
  let doe := yoe * 365 + yoe / 4 + doy - yoe / 100
  era * 146097 + doe

/-- minute: 0 when the timestamp does not parse -/
def minute (l : List Char) : Nat :=
  if l.length < 16 then 0 else
  if l.getD 13 ' ' != ':' then 0 else
  let y := dig2 l 0 * 100 + dig2 l 2
  let mo := dig2 l 5
  let d := dig2 l 8
  let hh := dig2 l 11
  let mi := dig2 l 14
  if mo < 1 || 12 < mo then 0 else
  if d < 1 || 31 < d then 0 else
  if 23 < hh || 59 < mi then 0 else
  if y < 1 then 0 else
  days y mo d * 1440 + hh * 60 + (mi + 1)

def absd (a b : Nat) : Nat := if b < a then a - b else b - a

/-! SHA-256 and HMAC-SHA256, from the seeded constants (codebook.om hmb/hmac/mkk0). -/
def kTab : Array UInt32 := #[1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580, 3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986, 2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895, 666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037, 2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344, 430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779, 1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]
def hInit : Array UInt32 := #[1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225]
def rotr (x n : UInt32) : UInt32 := (x >>> n) ||| (x <<< (32 - n))

def compress (hs : Array UInt32) (m : Array UInt8) (o : Nat) : Array UInt32 := Id.run do
  let mut w : Array UInt32 := #[]
  for i in [0:16] do
    let by_ (j : Nat) : UInt32 := (m[o + 4 * i + j]!).toUInt32
    w := w.push ((by_ 0 <<< 24) ||| (by_ 1 <<< 16) ||| (by_ 2 <<< 8) ||| by_ 3)
  for i in [16:64] do
    let x := w[i - 15]!
    let y := w[i - 2]!
    let s0 := rotr x 7 ^^^ rotr x 18 ^^^ (x >>> 3)
    let s1 := rotr y 17 ^^^ rotr y 19 ^^^ (y >>> 10)
    w := w.push (w[i - 16]! + s0 + w[i - 7]! + s1)
  let mut a := hs[0]!
  let mut b := hs[1]!
  let mut c := hs[2]!
  let mut d := hs[3]!
  let mut e := hs[4]!
  let mut f := hs[5]!
  let mut g := hs[6]!
  let mut h := hs[7]!
  for i in [0:64] do
    let t1 := h + (rotr e 6 ^^^ rotr e 11 ^^^ rotr e 25) + ((e &&& f) ^^^ ((~~~e) &&& g)) + kTab[i]! + w[i]!
    let t2 := (rotr a 2 ^^^ rotr a 13 ^^^ rotr a 22) + ((a &&& b) ^^^ (a &&& c) ^^^ (b &&& c))
    h := g; g := f; f := e; e := d + t1; d := c; c := b; b := a; a := t1 + t2
  return #[hs[0]! + a, hs[1]! + b, hs[2]! + c, hs[3]! + d, hs[4]! + e, hs[5]! + f, hs[6]! + g, hs[7]! + h]

def hex8 (x : UInt32) : String :=
  let s := String.ofList (Nat.toDigits 16 x.toNat)
  String.ofList (List.replicate (8 - s.length) '0') ++ s

def shaW (bs : List UInt8) : Array UInt32 := Id.run do
  let bytes : Array UInt8 := bs.toArray
  let len := bytes.size
  let k := (64 - (len + 9) % 64) % 64
  let mut m := bytes.push 0x80
  for _ in [0:k] do m := m.push 0
  let bits := len * 8
  for i in [0:8] do m := m.push ((bits >>> (8 * (7 - i))) % 256).toUInt8
  let mut hs := hInit
  for blk in [0:m.size / 64] do hs := compress hs m (64 * blk)
  return hs

def toB (msg : List Char) : List UInt8 := msg.map fun ch => ch.toNat.toUInt8
def sha256 (msg : List Char) : String := String.join ((shaW (toB msg)).toList.map hex8)
def shaB (bs : List UInt8) : List UInt8 :=
  (shaW bs).toList.flatMap fun (w : UInt32) => [(w >>> 24).toUInt8, (w >>> 16).toUInt8, (w >>> 8).toUInt8, w.toUInt8]
def hexB (bs : List UInt8) : String := String.join (bs.map fun b =>
  let s := String.ofList (Nat.toDigits 16 b.toNat)
  if s.length < 2 then "0" ++ s else s)
def k0 (key : List UInt8) : List UInt8 :=
  let k := if 64 < key.length then shaB key else key
  k ++ List.replicate (64 - k.length) 0
def hmacHex (key msg : List UInt8) : String :=
  let kz := k0 key
  hexB (shaB (kz.map (· ^^^ 0x5c) ++ shaB (kz.map (· ^^^ 0x36) ++ msg)))

/-! The codebook verify (codebook.om verl..verl4), as trit runs it: quiet, counters in a table. -/
structure VC where
  cs : String
  codes : List String
  key : List UInt8

def BIG : Nat := 9223372036854775807
def isHex (c : Char) : Bool := isDig c || ('a' ≤ c && c ≤ 'f')
def numOf (c : List Char) : Nat := c.foldl (fun a ch => a * 10 + (ch.toNat - 48)) 0

/-- ctrval: 1..18 digits, no leading zero, else 0. -/
def ctrval (t : String) : Nat :=
  let c := t.toList
  if c.length == 0 || 18 < c.length || c.head? == some '0' || !c.all isDig then 0 else numOf c

/-- decl + the code split: each code ends at the first group below 900; a dangling escape drops. -/
def codesOf : List Char → List Char → List (List Char)
  | a :: b :: c :: rest, cur =>
    if numOf [a, b, c] < 900 then (cur ++ [a, b, c]) :: codesOf rest [] else codesOf rest (cur ++ [a, b, c])
  | _, _ => []

/-- tsok: YYYY-MM-DDTHH:MM, 16 bytes (codebook.om ntsok / tsok). -/
def tsok (ts : String) : Bool :=
  let c := ts.toList
  decide (c.length = 16) && (List.range 16).all fun i =>
    let ch := c.getD i ' '
    if i == 4 || i == 7 then ch == '-'
    else if i == 10 then ch == 'T'
    else if i == 13 then ch == ':'
    else isDig ch

/-- verifyM: some (sender, counter, ts, has a 3xx) exactly when format, codebook id, codes and MAC
    all check (every refusal before `stale` / `badto` in codebook.om's order). Lane is bound in the MAC. -/
def verifyM (vc : VC) (lane : Char) (l : List Char) : Option (String × Nat × String × Bool) :=
  let (body, _) := lfmt l
  if body.length != 6 then none else
  if !tsok (body.getD 0 "") then none else
  let fs := fields l
  if fs.length < 2 then none else
  let lf := fs.getD (fs.length - 1) ""
  if lf.length < 5 then none else
  let ps := lf.splitOn ":"
  if ps.getD 0 "" != "ocb2" || ps.length < 5 || ps.getD 4 "" == "" then none else
  let s := body.getD 1 ""
  if s.length == 0 || 64 < s.length || !s.toList.all okch then none else
  if ps.length != 5 then none else
  let mac := ps.getD 4 ""
  if mac.length != 64 || !mac.toList.all isHex then none else
  if (ps.getD 1 "").length != 64 then none else
  let ct := ps.getD 2 ""
  let c := ctrval ct
  if c == 0 || ps.getD 1 "" != vc.cs then none else
  let ds := (ps.getD 3 "").toList
  if ds.length % 3 != 0 || !ds.all isDig then none else
  let cds := codesOf ds []
  if (cds.map List.length).sum != ds.length then none else
  if !cds.all (fun cd => vc.codes.contains (String.ofList cd)) then none else
  let ts := body.getD 0 ""
  let msg := "ocb2|" ++ vc.cs ++ "|" ++ ct ++ "|" ++ String.singleton lane ++ "|" ++
    ts ++ "|" ++ s ++ "|" ++ body.getD 2 "" ++ "|" ++ body.getD 3 "" ++ "|" ++
    body.getD 4 "" ++ "|" ++ body.getD 5 "" ++ "|" ++ String.ofList ds
  if hmacHex vc.key (toB msg.toList) != mac then none else
  some (s, c, ts, cds.any fun cd => cd.length == 3 && 300 ≤ numOf cd && numOf cd < 400)

def tsGe (last ts : String) : Bool := last == "" || (decide (last.length = ts.length) && decide (last ≤ ts))

/-- verify: verifyM plus the counter and ts checks (fresh = strictly above last counter and ts ≥ last ts). -/
def verify (vc : VC) (lane : Char) (last : String → Nat × String) (l : List Char) :
    Option (String × Nat × Bool × Bool) :=
  (verifyM vc lane l).map fun (s, c, ts, e) =>
    let (lc, lts) := last s
    (s, c, decide (lc < c) && tsGe lts ts, e)

/-- rdctf: the counter file; (0, "") when absent, (BIG, "") when malformed (fail closed).
    Form is "<counter> <ts>\n"; a lone counter (old form) is accepted with an empty last ts. -/
def rdctf : Option (List Char) → Nat × String
  | none => (0, "")
  | some c0 =>
    let c := c0.take 128
    if c.length == 0 then (BIG, "") else
    let m := if c.getLast? == some '\n' then c.dropLast else c
    match m.idxOf? ' ' with
    | none =>
      if m.length == 0 || 18 < m.length || !m.all isDig then (BIG, "") else (numOf m, "")
    | some k =>
      let ctr := m.take k
      let ts := String.ofList (m.drop (k + 1))
      if ctr.length == 0 || 18 < ctr.length || !ctr.all isDig then (BIG, "") else (numOf ctr, ts)

abbrev Tbl := List (String × Nat × String)
def tget (t : Tbl) (s : String) : Nat × String := ((t.find? (·.1 == s)).map (fun e => (e.2.1, e.2.2))).getD (0, "")
def tput (t : Tbl) (s : String) (c : Nat) (ts : String) : Tbl :=
  if t.any (·.1 == s) then t.map fun (s', c', ts') =>
    if s' == s then (if c' < c then (s', c, ts) else (s', c', ts')) else (s', c', ts')
  else t ++ [(s, c, ts)]

abbrev VR := Option (String × Nat × Bool × Bool)
def isTwo : VR → Bool
  | some (_, _, f, e) => f && e
  | none => false
def freshOf : VR → Option (String × Nat)
  | some (s, c, true, _) => some (s, c)
  | _ => none

/-- max of file and table last-counter (and the ts that goes with the winner). -/
def lastOf (fc : String → Nat × String) (t : Tbl) (s : String) : Nat × String :=
  let (fv, fts) := fc s
  let (tv, tts) := tget t s
  if fv < tv then (tv, tts) else (fv, fts)

/-- Destination binding for a signed line: 6 content fields and `to` equals the reading bot. -/
def destOk (l : List Char) (bot : String) : Bool :=
  decide ((lfmt l).1.length = 6) && decide ((lfmt l).1.getD 2 "" = bot)

/-- verified (trit.om) = verx in table mode, with to = bot and the file's lane in the MAC.
    A 6-field line whose `to` is not the bot never verifies. -/
def vline (vc : Option VC) (fc : String → Nat × String) (t : Tbl) (bot : String) (lane : Char)
    (l : List Char) : VR × Tbl :=
  match vc with
  | none => (none, t)
  | some v =>
    if destOk l bot then
      let fs := (lfmt l).1
      let r := verify v lane (lastOf fc t) l
      (r, match r with
        | some (s, c, true, _) => tput t s c (fs.getD 0 "")
        | _ => t)
    else (none, t)

/-- lvl: 2 only from a verified, fresh line with a 3xx code; fyi 0; anything else 1. -/
def lvl (r : VR) (l : List Char) : Trit :=
  if isTwo r then .two else if lnkind l == .zero then .zero else .one

/-- admit + cntwin + seenc: only MAC-good lines count, once per (sender, counter). -/
def admit (allow : List String) (acc : List (String × Nat × Nat)) (r : VR) (l : List Char) :
    Option (List (String × Nat × Nat)) :=
  match (fields l)[1]? with
  | none => none
  | some s =>
    if !okname allow s then none else
    let m := minute l
    if m == 0 then none else
    match r with
    | none => some acc
    | some (_, c, _, _) =>
      if acc.any (fun (s', _, c') => s' == s && c' == c) then some acc else
      if 3 ≤ (acc.filter fun (s', m', _) => s' == s && absd m' m < 60).length then none
      else some (acc ++ [(s, m, c)])

/-- scane: every complete content line is verified and goes through admission. -/
def scane (vc : Option VC) (fc : String → Nat × String) (allow : List String) (st : Nat)
    (ls : List (Nat × List Char)) : Trit × Nat × Tbl :=
  let r := ls.foldl (fun (acc, t, rej, tb) (p, l) =>
    if !ists l then (acc, t, rej, tb) else
    let (v, tb') := vline vc fc tb "a" 'e' l
    match admit allow acc v l with
    | some acc' => (acc', if st ≤ p then t.max (lvl v l) else t, rej, tb')
    | none => (acc, t, if st ≤ p then rej + 1 else rej, tb'))
    (([] : List (String × Nat × Nat)), Trit.zero, 0, ([] : Tbl))
  (r.2.1, r.2.2.1, r.2.2.2)

/-- one step of scann -/
def nstep (vc : Option VC) (fc : String → Nat × String) (st : Nat) (x : Trit × Tbl) (y : Nat × List Char) : Trit × Tbl :=
  if st ≤ y.1 && ists y.2 then
    let (v, tb') := vline vc fc x.2 "a" 'n' y.2
    (x.1.max (lvl v y.2), tb')
  else x

def scann (vc : Option VC) (fc : String → Nat × String) (t0 : Tbl) (st : Nat) (ls : List (Nat × List Char)) : Trit :=
  (ls.foldl (nstep vc fc st) (.zero, t0)).1

/-- rdcur: the unread start, from at most the first 128 cursor bytes. -/
def rdcur (cur : Option (List Char)) (fb : List Char) : Nat :=
  match cur with
  | none => 0
  | some c0 =>
    let cb := c0.take 128
    let n := cb.length
    if n < 66 then 0 else
    let digits := cb.takeWhile (· != ' ')
    if !digits.all isDig then 0 else
    let i := digits.length
    let bad := (List.range i).any fun j =>
      decide (100000000000000 < (digits.take j).foldl (fun a ch => a * 10 + (ch.toNat - 48)) 0)
    if bad then 0 else
    let off := digits.foldl (fun a ch => a * 10 + (ch.toNat - 48)) 0
    if off == 0 || fb.length < off then 0 else
    if n < i + 65 then 0 else
    if fb.getD (off - 1) ' ' != '\n' then 0 else
    if (sha256 (fb.take off)).toList == (cb.drop (i + 1)).take 64 then off else 0

/-- lastnl + mktok: the token for a lane. -/
def token (lane : Char) (fb : List Char) : String :=
  let off := fb.length - (fb.reverse.idxOf '\n')
  String.singleton lane ++ toString off ++ ":" ++ sha256 (fb.take off)

def digit : Trit → String
  | .zero => "0" | .one => "1" | .two => "2"

/-- state + emit + rejout + main's exit status for one bot `a` (stdout, stderr, status). -/
def runBot (vc : Option VC) (fc : String → Nat × String) (allow : List String) (nm em nc ec : Option (List Char)) :
    String × String × Nat :=
  let (te, rej, tb) := match em with
    | none => (Trit.zero, 0, ([] : Tbl))
    | some e => scane vc fc allow (rdcur ec e) (linesOf e)
  let err := if 0 < rej then "rejected a " ++ toString rej ++ "\n" else ""
  let (t, tok) : Trit × String :=
    if te == .two then (te, token 'e' (em.getD [])) else
    let tn := match nm with
      | none => Trit.zero
      | some n => scann vc fc tb (rdcur nc n) (linesOf n)
    if tn != .zero then (tn, token 'n' (nm.getD [])) else
    if te != .zero then (te, token 'e' (em.getD [])) else (.zero, "")
  if t == .zero then ("", err, 1) else ("a " ++ digit t ++ " " ++ tok ++ "\n", err, 0)

/-! Properties of the shipped logic. -/

/-- A 2 comes only from a line whose codebook verify returned fresh with a 3xx code. -/
theorem lvl_two (r : VR) (l : List Char) (h : lvl r l = .two) : isTwo r = true := by
  unfold lvl at h
  by_cases hr : isTwo r = true
  · exact hr
  · simp only [hr, Bool.false_eq_true, ite_false] at h
    split at h <;> cases h

theorem isTwo_some (r : VR) (h : isTwo r = true) : ∃ s c, r = some (s, c, true, true) := by
  match r, h with
  | some (s, c, true, true), _ => exact ⟨s, c, rfl⟩

/-- In trit, the verify result is exactly codebook verify against max(counter file, table). -/
theorem vline_none (fc : String → Nat × String) (t : Tbl) (bot : String) (lane : Char) (l : List Char) :
    vline none fc t bot lane l = (none, t) := rfl

/-- verify refuses every line whose MAC does not check, and a fresh line has a strictly greater counter. -/
theorem verify_fresh (v : VC) (lane : Char) (last : String → Nat × String) (l : List Char)
    (s : String) (c : Nat) (e : Bool)
    (h : verify v lane last l = some (s, c, true, e)) : (last s).1 < c := by
  unfold verify at h
  cases hm : verifyM v lane l with
  | none => simp [hm] at h
  | some x =>
    obtain ⟨s', c', ts', e'⟩ := x
    simp [hm] at h
    obtain ⟨rfl, rfl, ⟨hlt, _⟩, rfl⟩ := h
    exact hlt

theorem lvl_ne_two_none (l : List Char) : lvl none l ≠ .two := by
  intro h; have := lvl_two _ _ h; simp [isTwo] at this

theorem max_ne_two (a b : Trit) (ha : a ≠ .two) (hb : b ≠ .two) : a.max b ≠ .two := by
  cases a <;> cases b <;> simp_all <;> decide

/-- Without a codebook and key nothing in the normal lane is a 2 (STOP, stop tags included). -/
theorem scann_capped (fc : String → Nat × String) (t0 : Tbl) (st : Nat) (ls : List (Nat × List Char)) :
    scann none fc t0 st ls ≠ .two := by
  unfold scann
  suffices h : ∀ (xs : List (Nat × List Char)) (x : Trit × Tbl), x.1 ≠ .two →
      (xs.foldl (nstep none fc st) x).1 ≠ .two from h ls _ (fun h => by cases h)
  intro xs
  induction xs with
  | nil => intro x hx; exact hx
  | cons y ys ih =>
    intro x hx
    simp only [List.foldl_cons]
    apply ih
    unfold nstep
    split
    · exact max_ne_two _ _ hx (lvl_ne_two_none _)
    · exact hx

/-- Never starved: when the emergency lane is at 2 (a verified 3xx), the output is the emergency
    lane's whatever the normal lane holds. -/
theorem emergency_first (vc : Option VC) (fc : String → Nat × String) (allow : List String)
    (em ec n1 n2 c1 c2 : Option (List Char))
    (h : (match em with
          | none => (Trit.zero, 0, ([] : Tbl))
          | some e => scane vc fc allow (rdcur ec e) (linesOf e)).1 = .two) :
    runBot vc fc allow n1 em c1 ec = runBot vc fc allow n2 em c2 ec := by
  unfold runBot
  revert h
  generalize (match em with
          | none => (Trit.zero, 0, ([] : Tbl))
          | some e => scane vc fc allow (rdcur ec e) (linesOf e)) = r
  intro h
  obtain ⟨te, rej, tb⟩ := r
  simp only at h ⊢
  subst h
  simp

/-- A 2 from verified+lvl requires the 6-field form and to = the bot being read. -/
theorem lvl_two_bound (v : VC) (fc : String → Nat × String) (t : Tbl) (bot : String) (lane : Char)
    (l : List Char) (h : lvl (vline (some v) fc t bot lane l).1 l = .two) :
    (lfmt l).1.length = 6 ∧ (lfmt l).1.getD 2 "" = bot := by
  have ht := lvl_two _ _ h
  unfold vline at ht
  cases hb : destOk l bot
  · simp [hb, isTwo] at ht
  · have ⟨h1, h2⟩ := (Bool.and_eq_true _ _).mp hb
    exact ⟨of_decide_eq_true h1, of_decide_eq_true h2⟩

end TritBin

#print axioms TritSignal.classify_append
#print axioms TritSignal.scan_correct
#print axioms TritSignal.never_starved
#print axioms TritSignal.ack_race
#print axioms TritSignal.refused_ack_unchanged
#print axioms TritSignal.classify_total
#print axioms TritBin.scann_capped
#print axioms TritBin.lvl_two
#print axioms TritBin.verify_fresh
#print axioms TritBin.isTwo_some
#print axioms TritBin.emergency_first
#print axioms TritBin.lvl_two_bound
