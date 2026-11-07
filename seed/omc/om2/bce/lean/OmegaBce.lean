/-
OmegaBce.lean: Lean 4 model and proof of omc rule `forbnd` (DRA-189).

Implementation: aien-dev/omega-mv seed/omc/omc.om, functions bce_q, bce_scan, bce_er, elemaddr,
sf_num, pushb (opt-in with the OM-2 lead line `om2 bce` / `om2 diag bce`).

The model is explicit and small. It is NOT the AArch64 code omc emits; the mapping from each model
construct to the omc function and emitted words is in seed/omc/om2/bce/README.md (section
"Implementation mapping"), together with the trusted-computing-base statement.

Machine integers are `BitVec 64` (registers are X registers; the for counter is a ulong; the latch
`add i 1` wraps mod 2^64). Bounds checks compare unsigned (CMP Xi, #len; B.HS trap 3).
No floats are involved: no index, count or length is a float, and the rule never looks at values
other than the counter, the count and the length.
-/
namespace OmegaBce

abbrev Word := BitVec 64
/-- a pool register (omc nm_reg) -/
abbrev Reg := Nat
/-- an array name entry (omc name index) -/
abbrev Arr := Nat
abbrev Mem := Arr → Word → Word

/-- Machine state: X registers and memory. `mem a i` is element i of array a; for i past the array it
is whatever the machine holds there (the model does not need it to be meaningful). -/
structure St where
  reg : Reg → Word
  mem : Mem

def St.set (s : St) (r : Reg) (v : Word) : St :=
  { s with reg := fun q => if q = r then v else s.reg q }

def St.store (s : St) (a : Arr) (i w : Word) : St :=
  { s with mem := fun b j => if b = a ∧ j = i then w else s.mem b j }

/-- Values. `get a ix chk`: element ix of sized array a; `chk` is whether omc emits the run-time check
(CMP / B.HS trap 3). `op` is any word operation with its own traps (add, sub, conversions, ...). -/
inductive Ex where
  | reg (r : Reg)
  | lit (w : Word)
  | get (a : Arr) (ix : Ex) (chk : Bool)
  | op (f : Word → Word → Except Nat Word) (x y : Ex)

/-- Statements. `forN r k g body`: `for r ulong k` with k a number (sf_num), g the optional `bound N`.
`forV r kr n body`: a count that is a value in register kr, with its bound n (sf_val).
`call dst arg f`: a call or host word; it sees the argument and memory and may change memory and
the destination register only (the callee cannot write the caller's registers). -/
inductive Stmt where
  | skip
  | assign (r : Reg) (e : Ex)
  | put (a : Arr) (ix v : Ex) (chk : Bool)
  | call (dst : Reg) (arg : Ex) (f : Word → Mem → Except Nat (Word × Mem))
  | seq (p q : Stmt)
  | ite (c : Ex) (p q : Stmt)
  | whileB (c : Ex) (n : Nat) (body : Stmt)
  | forN (r : Reg) (k : Word) (g : Option Nat) (body : Stmt)
  | forV (r : Reg) (kr : Reg) (n : Nat) (body : Stmt)
  | brk
  | cont
  | trap (c : Nat)

/-- Outcomes: normal end, break, continue, a trap code, or out of fuel (an unguarded loop that has not
finished within the fuel; equality for every fuel covers every terminating and diverging run). -/
inductive Out where
  | norm (s : St)
  | brk (s : St)
  | cont (s : St)
  | trap (c : Nat)
  | fuel

section Sem
variable (len : Arr → Word)

/-- Evaluation, left to right; the first trap wins. A checked get traps 3 when the index is not below
the array's length (unsigned). -/
def eval : Ex → St → Except Nat Word
  | .reg r, s => .ok (s.reg r)
  | .lit w, _ => .ok w
  | .get a ix chk, s =>
      match eval ix s with
      | .error c => .error c
      | .ok i => if chk && !(decide (i < len a)) then .error 3 else .ok (s.mem a i)
  | .op f x y, s =>
      match eval x s with
      | .error c => .error c
      | .ok u =>
        match eval y s with
        | .error c => .error c
        | .ok w => f u w

/-- while c bound n: head: c false -> exit; passes left 0 -> trap 4; body; back to the head. -/
def whileIter (c : Ex) (run : St → Out) : Nat → St → Out
  | 0, s =>
      match eval len c s with
      | .error e => .trap e
      | .ok w => if w = 0 then .norm s else .trap 4
  | n + 1, s =>
      match eval len c s with
      | .error e => .trap e
      | .ok w =>
        if w = 0 then .norm s else
        match run s with
        | .norm s' => whileIter c run n s'
        | .cont s' => whileIter c run n s'
        | .brk s' => .norm s'
        | o => o

/-- for loops: head: not r < k -> exit (unsigned, B.HS); no passes left -> `ex` (trap 4 with a bound,
out of fuel without); body; latch r = r + 1 (wrapping); continue goes to the latch. -/
def forIter (r : Reg) (k : St → Word) (run : St → Out) (ex : Out) : Nat → St → Out
  | 0, s => if s.reg r < k s then ex else .norm s
  | n + 1, s =>
      if s.reg r < k s then
        match run s with
        | .norm s' => forIter r k run ex n (s'.set r (s'.reg r + 1))
        | .cont s' => forIter r k run ex n (s'.set r (s'.reg r + 1))
        | .brk s' => .norm s'
        | o => o
      else .norm s

def exec (fuel : Nat) : Stmt → St → Out
  | .skip, s => .norm s
  | .assign r e, s =>
      match eval len e s with
      | .error c => .trap c
      | .ok v => .norm (s.set r v)
  | .put a ix v chk, s =>
      match eval len ix s with
      | .error c => .trap c
      | .ok i =>
        match eval len v s with
        | .error c => .trap c
        | .ok w => if chk && !(decide (i < len a)) then .trap 3 else .norm (s.store a i w)
  | .call d arg f, s =>
      match eval len arg s with
      | .error c => .trap c
      | .ok x =>
        match f x s.mem with
        | .error c => .trap c
        | .ok (y, m) => .norm ({ s with mem := m }.set d y)
  | .seq p q, s =>
      match exec fuel p s with
      | .norm s' => exec fuel q s'
      | o => o
  | .ite c p q, s =>
      match eval len c s with
      | .error e => .trap e
      | .ok w => if w = 0 then exec fuel q s else exec fuel p s
  | .whileB c n body, s => whileIter len c (exec fuel body) n s
  | .forN r k g body, s =>
      match g with
      | some n => forIter r (fun _ => k) (exec fuel body) (.trap 4) n (s.set r 0)
      | none => forIter r (fun _ => k) (exec fuel body) .fuel fuel (s.set r 0)
  | .forV r kr n body, s => forIter r (fun t => t.reg kr) (exec fuel body) (.trap 4) n (s.set r 0)
  | .brk, s => .brk s
  | .cont, s => .cont s
  | .trap c, _ => .trap c

end Sem

/-- Registers a statement can write (omc: a line whose first word is the name, plus a for loop's own
counter). bce_scan refuses a loop when any body line starts with the counter's name; every
statement below that writes register c is such a line, so omc admitting a loop implies
`writes c body = false`. -/
def writes (c : Reg) : Stmt → Bool
  | .skip => false
  | .assign r _ => r == c
  | .put .. => false
  | .call d _ _ => d == c
  | .seq p q => writes c p || writes c q
  | .ite _ p q => writes c p || writes c q
  | .whileB _ _ b => writes c b
  | .forN r _ _ b => r == c || writes c b
  | .forV r _ _ b => r == c || writes c b
  | .brk => false
  | .cont => false
  | .trap _ => false

section Rule
variable (len : Arr → Word)

/-- bce_er: the index is exactly the register of an admitted counter whose count is at most the
array's length. -/
def safeIx (act : List (Reg × Word)) (a : Arr) : Ex → Bool
  | .reg r => act.any (fun p => p.1 == r && decide (p.2 ≤ len a))
  | _ => false

def eraseE (act : List (Reg × Word)) : Ex → Ex
  | .reg r => .reg r
  | .lit w => .lit w
  | .get a ix chk => .get a (eraseE act ix) (chk && !(safeIx len act a ix))
  | .op f x y => .op f (eraseE act x) (eraseE act y)

/-- The pass. bce_q admits `for r ulong k` (k a number, k >= 1) when the body does not write r; its
body is then compiled with (r, k) among the open admitted for blocks (bbce). -/
def erase (act : List (Reg × Word)) : Stmt → Stmt
  | .skip => .skip
  | .assign r e => .assign r (eraseE len act e)
  | .put a ix v chk => .put a (eraseE len act ix) (eraseE len act v) (chk && !(safeIx len act a ix))
  | .call d arg f => .call d (eraseE len act arg) f
  | .seq p q => .seq (erase act p) (erase act q)
  | .ite c p q => .ite (eraseE len act c) (erase act p) (erase act q)
  | .whileB c n b => .whileB (eraseE len act c) n (erase act b)
  | .forN r k g b =>
      if k ≠ 0 ∧ writes r b = false then .forN r k g (erase ((r, k) :: act) b)
      else .forN r k g (erase act b)
  | .forV r kr n b => .forV r kr n (erase act b)
  | .brk => .brk
  | .cont => .cont
  | .trap c => .trap c

end Rule

/-- Every admitted counter is below its count. -/
def Inv (act : List (Reg × Word)) (s : St) : Prop := ∀ p ∈ act, s.reg p.1 < p.2

/-- No admitted counter is written by the statement. -/
def NoW (act : List (Reg × Word)) (p : Stmt) : Prop := ∀ q ∈ act, writes q.1 p = false

/-- The register c keeps value v in every outcome that continues execution. -/
def Out.keeps (c : Reg) (v : Word) : Out → Prop
  | .norm s => s.reg c = v
  | .brk s => s.reg c = v
  | .cont s => s.reg c = v
  | _ => True

theorem set_other (s : St) (r c : Reg) (v : Word) (h : r ≠ c) : (s.set r v).reg c = s.reg c := by
  simp [St.set]; intro hc; exact absurd hc.symm h

theorem set_same (s : St) (r : Reg) (v : Word) : (s.set r v).reg r = v := by
  simp [St.set]

theorem store_reg (s : St) (a : Arr) (i w : Word) : (s.store a i w).reg = s.reg := rfl

section Proofs
variable (len : Arr → Word)

theorem forIter_keeps (c : Reg) (r : Reg) (hr : r ≠ c) (k : St → Word) (run : St → Out) (ex : Out)
    (hex : ∀ v, ex.keeps c v)
    (hrun : ∀ s, (run s).keeps c (s.reg c)) :
    ∀ n s, (forIter r k run ex n s).keeps c (s.reg c) := by
  intro n
  induction n with
  | zero =>
    intro s; simp only [forIter]; split
    · exact hex _
    · simp [Out.keeps]
  | succ n ih =>
    intro s; simp only [forIter]; split
    · have h := hrun s
      split
      · next s' heq =>
        rw [heq] at h; simp [Out.keeps] at h
        have := ih (s'.set r (s'.reg r + 1)); rw [set_other _ _ _ _ hr, h] at this; exact this
      · next s' heq =>
        rw [heq] at h; simp [Out.keeps] at h
        have := ih (s'.set r (s'.reg r + 1)); rw [set_other _ _ _ _ hr, h] at this; exact this
      · next s' heq => rw [heq] at h; simpa [Out.keeps] using h
      · next o h1 h2 h3 =>
        cases o <;> simp_all [Out.keeps]
    · simp [Out.keeps]

theorem whileIter_keeps (c : Reg) (cond : Ex) (run : St → Out)
    (hrun : ∀ s, (run s).keeps c (s.reg c)) :
    ∀ n s, (whileIter len cond run n s).keeps c (s.reg c) := by
  intro n
  induction n with
  | zero =>
    intro s; simp only [whileIter]; split
    · simp [Out.keeps]
    · split <;> simp [Out.keeps]
  | succ n ih =>
    intro s; simp only [whileIter]; split
    · simp [Out.keeps]
    · split
      · simp [Out.keeps]
      · have h := hrun s
        split
        · next s' heq => rw [heq] at h; simp [Out.keeps] at h; rw [← h]; exact ih s'
        · next s' heq => rw [heq] at h; simp [Out.keeps] at h; rw [← h]; exact ih s'
        · next s' heq => rw [heq] at h; simpa [Out.keeps] using h
        · next o h1 h2 h3 => cases o <;> simp_all [Out.keeps]

/-- A statement that does not write c leaves c unchanged on every continuing outcome. -/
theorem exec_keeps (fuel : Nat) (c : Reg) :
    ∀ (p : Stmt) (s : St), writes c p = false → (exec len fuel p s).keeps c (s.reg c) := by
  intro p
  induction p with
  | skip => intro s _; simp [exec, Out.keeps]
  | assign r e =>
    intro s hw; simp [writes] at hw; simp only [exec]; split
    · simp [Out.keeps]
    · simp [Out.keeps]; exact set_other _ _ _ _ hw
  | put a ix v chk =>
    intro s _; simp only [exec]; split
    · simp [Out.keeps]
    · split
      · simp [Out.keeps]
      · split <;> simp [Out.keeps, store_reg]
  | call d arg f =>
    intro s hw; simp [writes] at hw; simp only [exec]; split
    · simp [Out.keeps]
    · split
      · simp [Out.keeps]
      · simp [Out.keeps]; rw [set_other _ _ _ _ hw]
  | seq p q ihp ihq =>
    intro s hw; simp [writes] at hw; simp only [exec]
    have h := ihp s hw.1
    split
    · next s' heq => rw [heq] at h; simp [Out.keeps] at h; rw [← h]; exact ihq s' hw.2
    · next o hne => cases o <;> simp_all [Out.keeps]
  | ite cnd p q ihp ihq =>
    intro s hw; simp [writes] at hw; simp only [exec]; split
    · simp [Out.keeps]
    · split
      · exact ihq s hw.2
      · exact ihp s hw.1
  | whileB cnd n b ih =>
    intro s hw; simp [writes] at hw; simp only [exec]
    exact whileIter_keeps len c cnd _ (fun t => ih t hw) n s
  | forN r k g b ih =>
    intro s hw; simp [writes] at hw
    have hr : r ≠ c := hw.1
    cases g with
    | some n =>
      simp only [exec]
      have := forIter_keeps c r hr (fun _ => k) (exec len fuel b) (.trap 4) (fun _ => by simp [Out.keeps])
        (fun t => ih t hw.2) n (s.set r 0)
      rwa [set_other _ _ _ _ hr] at this
    | none =>
      simp only [exec]
      have := forIter_keeps c r hr (fun _ => k) (exec len fuel b) .fuel (fun _ => by simp [Out.keeps])
        (fun t => ih t hw.2) fuel (s.set r 0)
      rwa [set_other _ _ _ _ hr] at this
  | forV r kr n b ih =>
    intro s hw; simp [writes] at hw
    have hr : r ≠ c := hw.1
    simp only [exec]
    have := forIter_keeps c r hr (fun t => t.reg kr) (exec len fuel b) (.trap 4)
      (fun _ => by simp [Out.keeps]) (fun t => ih t hw.2) n (s.set r 0)
    rwa [set_other _ _ _ _ hr] at this
  | brk => intro s _; simp [exec, Out.keeps]
  | cont => intro s _; simp [exec, Out.keeps]
  | trap _ => intro s _; simp [exec, Out.keeps]

/-- An admitted index is in bounds. -/
theorem safe_inbounds (act : List (Reg × Word)) (s : St) (hinv : Inv act s) (a : Arr) (ix : Ex)
    (h : safeIx len act a ix = true) : ∃ r, ix = .reg r ∧ s.reg r < len a := by
  cases ix with
  | reg r =>
    refine ⟨r, rfl, ?_⟩
    simp [safeIx, List.any_eq_true] at h
    obtain ⟨r', k, hmem, hr, hk⟩ := h
    subst hr
    have h1 := hinv (r', k) hmem
    simp at h1
    rw [BitVec.lt_def] at h1 ⊢; rw [BitVec.le_def] at hk; omega
  | lit w => simp [safeIx] at h
  | get a' ix' chk => simp [safeIx] at h
  | op f x y => simp [safeIx] at h

/-- Erasure does not change any value under the invariant. -/
theorem eval_erase (act : List (Reg × Word)) (s : St) (hinv : Inv act s) :
    ∀ e, eval len (eraseE len act e) s = eval len e s := by
  intro e
  induction e with
  | reg r => rfl
  | lit w => rfl
  | get a ix chk ih =>
    simp only [eraseE, eval, ih]
    split
    · rfl
    · next i hi =>
      by_cases hs : safeIx len act a ix = true
      · obtain ⟨r, hix, hlt⟩ := safe_inbounds len act s hinv a ix hs
        subst hix
        simp [eval] at hi; subst hi
        simp [hs, hlt]
      · simp at hs; simp [hs]
  | op f x y ihx ihy => simp only [eraseE, eval, ihx, ihy]

theorem inv_set (act : List (Reg × Word)) (s : St) (r : Reg) (v : Word) (hinv : Inv act s)
    (hr : ∀ q ∈ act, q.1 ≠ r) : Inv act (s.set r v) := by
  intro q hq; rw [set_other _ _ _ _ (fun h => hr q hq h.symm)]; exact hinv q hq

theorem inv_keep (act : List (Reg × Word)) (s s' : St) (hinv : Inv act s)
    (h : ∀ q ∈ act, s'.reg q.1 = s.reg q.1) : Inv act s' := by
  intro q hq; rw [h q hq]; exact hinv q hq

/-- Every continuing outcome of a statement that writes no admitted counter keeps the invariant. -/
theorem keeps_all (fuel : Nat) (act : List (Reg × Word)) (p : Stmt) (s : St) (hw : NoW act p) :
    ∀ q ∈ act, (exec len fuel p s).keeps q.1 (s.reg q.1) :=
  fun q hq => exec_keeps len fuel q.1 p s (hw q hq)

theorem forIter_erase (r : Reg) (k : St → Word) (run run' : St → Out)
    (ex : Out) (P : St → Prop)
    (hhead : ∀ s, P s → s.reg r < k s → run' s = run s)
    (hstep : ∀ s, P s → s.reg r < k s → ∀ s', (run s = .norm s' ∨ run s = .cont s') →
       P (s'.set r (s'.reg r + 1))) :
    ∀ n s, P s → forIter r k run' ex n s = forIter r k run ex n s := by
  intro n
  induction n with
  | zero => intro s _; simp [forIter]
  | succ n ih =>
    intro s hp
    simp only [forIter]
    by_cases hlt : s.reg r < k s
    · simp only [hlt, ite_true, hhead s hp hlt]
      split
      · next s' heq => exact ih _ (hstep s hp hlt s' (Or.inl heq))
      · next s' heq => exact ih _ (hstep s hp hlt s' (Or.inr heq))
      · rfl
      · rfl
    · simp [hlt]

theorem whileIter_erase (act : List (Reg × Word)) (c : Ex) (run run' : St → Out) (P : St → Prop)
    (hc : ∀ s, P s → eval len (eraseE len act c) s = eval len c s)
    (hrun : ∀ s, P s → run' s = run s)
    (hstep : ∀ s, P s → ∀ s', (run s = .norm s' ∨ run s = .cont s') → P s') :
    ∀ n s, P s → whileIter len (eraseE len act c) run' n s = whileIter len c run n s := by
  intro n
  induction n with
  | zero => intro s hp; simp only [whileIter, hc s hp]
  | succ n ih =>
    intro s hp
    simp only [whileIter, hc s hp, hrun s hp]
    split
    · rfl
    · split
      · rfl
      · split
        · next s' heq => exact ih _ (hstep s hp s' (Or.inl heq))
        · next s' heq => exact ih _ (hstep s hp s' (Or.inr heq))
        · rfl
        · rfl

/-- The pass preserves the meaning of every statement: same final state, same break / continue, same
trap code, same fuel exhaustion, from every state where the admitted counters are below their
counts, as long as the statement does not write an admitted counter. -/
theorem erase_correct (fuel : Nat) :
    ∀ (p : Stmt) (act : List (Reg × Word)) (s : St), Inv act s → NoW act p →
      exec len fuel (erase len act p) s = exec len fuel p s := by
  intro p
  induction p with
  | skip => intro act s _ _; rfl
  | assign r e => intro act s hinv _; simp only [erase, exec, eval_erase len act s hinv]
  | put a ix v chk =>
    intro act s hinv _
    simp only [erase, exec, eval_erase len act s hinv]
    split
    · rfl
    · next i hi =>
      split
      · rfl
      · next w hw =>
        by_cases hs : safeIx len act a ix = true
        · obtain ⟨r, hix, hlt⟩ := safe_inbounds len act s hinv a ix hs
          subst hix; simp [eval] at hi; subst hi
          simp [hs, hlt]
        · simp at hs; simp [hs]
  | call d arg f => intro act s hinv _; simp only [erase, exec, eval_erase len act s hinv]
  | seq p q ihp ihq =>
    intro act s hinv hw
    have hwp : NoW act p := fun x hx => by have := hw x hx; simp [writes] at this; exact this.1
    have hwq : NoW act q := fun x hx => by have := hw x hx; simp [writes] at this; exact this.2
    simp only [erase, exec, ihp act s hinv hwp]
    split
    · next s' heq =>
      apply ihq act s' _ hwq
      apply inv_keep act s s' hinv
      intro x hx; have := keeps_all len fuel act p s hwp x hx; rw [heq] at this; exact this
    · rfl
  | ite c p q ihp ihq =>
    intro act s hinv hw
    have hwp : NoW act p := fun x hx => by have := hw x hx; simp [writes] at this; exact this.1
    have hwq : NoW act q := fun x hx => by have := hw x hx; simp [writes] at this; exact this.2
    simp only [erase, exec, eval_erase len act s hinv]
    split
    · rfl
    · split
      · exact ihq act s hinv hwq
      · exact ihp act s hinv hwp
  | whileB c n b ih =>
    intro act s hinv hw
    have hwb : NoW act b := fun x hx => by have := hw x hx; simp [writes] at this; exact this
    simp only [erase, exec]
    apply whileIter_erase len act c (exec len fuel b) (exec len fuel (erase len act b)) (Inv act)
    · intro t ht; exact eval_erase len act t ht c
    · intro t ht; exact ih act t ht hwb
    · intro t ht t' h
      apply inv_keep act t t' ht; intro x hx
      have := keeps_all len fuel act b t hwb x hx
      rcases h with h | h <;> rw [h] at this <;> exact this
    · exact hinv
  | forN r k g b ih =>
    intro act s hinv hw
    have hwb : NoW act b := fun x hx => by have := hw x hx; simp [writes] at this; exact this.2
    have hra : ∀ x ∈ act, x.1 ≠ r := fun x hx => by
      have := hw x hx; simp [writes] at this; exact fun h => this.1 h.symm
    have hinv0 : Inv act (s.set r 0) := inv_set act s r 0 hinv hra
    -- after a pass and the latch the outer invariant still holds
    have hstep_outer : ∀ t, Inv act t → ∀ t', (exec len fuel b t = .norm t' ∨ exec len fuel b t = .cont t') →
        Inv act (t'.set r (t'.reg r + 1)) := by
      intro t ht t' h
      apply inv_set act t' r _ _ hra
      apply inv_keep act t t' ht; intro x hx
      have := keeps_all len fuel act b t hwb x hx
      rcases h with h | h <;> rw [h] at this <;> exact this
    by_cases hq : k ≠ 0 ∧ writes r b = false
    · -- admitted: the body is erased with (r, k) added
      have hwb' : NoW ((r, k) :: act) b := by
        intro x hx; simp at hx; rcases hx with hx | hx
        · subst hx; exact hq.2
        · exact hwb x hx
      have hhead : ∀ t, Inv act t → t.reg r < k →
          exec len fuel (erase len ((r, k) :: act) b) t = exec len fuel b t := by
        intro t ht hlt; apply ih ((r, k) :: act) t _ hwb'
        intro x hx; simp at hx; rcases hx with hx | hx
        · subst hx; exact hlt
        · exact ht x hx
      simp only [erase, hq, ne_eq, not_false_eq_true, and_self, ite_true, exec]
      cases g with
      | some n =>
        exact forIter_erase r (fun _ => k) _ _ _ (Inv act) (fun t ht hlt => hhead t ht hlt)
          (fun t ht _ t' h => hstep_outer t ht t' h) n _ hinv0
      | none =>
        exact forIter_erase r (fun _ => k) _ _ _ (Inv act) (fun t ht hlt => hhead t ht hlt)
          (fun t ht _ t' h => hstep_outer t ht t' h) fuel _ hinv0
    · -- not admitted: only the outer facts apply inside
      simp only [erase, hq, ite_false, exec]
      cases g with
      | some n =>
        exact forIter_erase r (fun _ => k) _ _ _ (Inv act) (fun t ht _ => ih act t ht hwb)
          (fun t ht _ t' h => hstep_outer t ht t' h) n _ hinv0
      | none =>
        exact forIter_erase r (fun _ => k) _ _ _ (Inv act) (fun t ht _ => ih act t ht hwb)
          (fun t ht _ t' h => hstep_outer t ht t' h) fuel _ hinv0
  | forV r kr n b ih =>
    intro act s hinv hw
    have hwb : NoW act b := fun x hx => by have := hw x hx; simp [writes] at this; exact this.2
    have hra : ∀ x ∈ act, x.1 ≠ r := fun x hx => by
      have := hw x hx; simp [writes] at this; exact fun h => this.1 h.symm
    simp only [erase, exec]
    apply forIter_erase r (fun t => t.reg kr) _ _ _ (Inv act) (fun t ht _ => ih act t ht hwb)
    · intro t ht _ t' h
      apply inv_set act t' r _ _ hra
      apply inv_keep act t t' ht; intro x hx
      have := keeps_all len fuel act b t hwb x hx
      rcases h with h | h <;> rw [h] at this <;> exact this
    · exact inv_set act s r 0 hinv hra
  | brk => intro act s _ _; rfl
  | cont => intro act s _ _; rfl
  | trap _ => intro act s _ _; rfl

/-- **Main theorem.** For every program, every array-length table, every fuel and every initial state,
the program compiled with rule forbnd behaves exactly as the program compiled with every check. -/
theorem bce_correct (fuel : Nat) (p : Stmt) (s : St) :
    exec len fuel (erase len [] p) s = exec len fuel p s :=
  erase_correct len fuel p [] s (fun _ h => by simp at h) (fun _ h => by simp at h)

end Proofs

/-! ## Negative controls: each premise of the rule is needed (the omc.om mutants klen, scan, reg). -/

/-- An outcome's trap code, if any (Out has functions inside, so compare this projection). -/
def Out.code : Out → Option Nat
  | .trap c => some c
  | _ => none

/-- Arrays 0 and 1, length 2 each. -/
def lens : Arr → Word := fun _ => 2#64
def st0 : St := ⟨fun _ => 0#64, fun _ _ => 0#64⟩

/-- A pass without the k <= len premise (mutant klen). -/
def eraseNoLen : List (Reg × Word) → Stmt → Stmt
  | act, .assign r (.get a (.reg i) true) =>
      .assign r (.get a (.reg i) (!(act.any (fun p => p.1 == i))))
  | act, .forN r k g b => .forN r k g (eraseNoLen ((r, k) :: act) b)
  | _, p => p

/-- for i ulong 3: x = get a i, with len a = 2: the third pass traps 3. -/
def pKgt : Stmt := .forN 0 3#64 none (.assign 1 (.get 0 (.reg 0) true))

theorem kgt_traps : (exec lens 10 pKgt st0).code = some 3 := by decide
theorem kgt_rule_keeps : (exec lens 10 (erase lens [] pKgt) st0).code = some 3 := by decide
theorem kgt_without_len_premise : (exec lens 10 (eraseNoLen [] pKgt) st0).code = none := by decide

/-- A pass without the body-write premise (mutant scan). -/
def eraseNoScan (len : Arr → Word) : List (Reg × Word) → Stmt → Stmt
  | act, .seq p q => .seq (eraseNoScan len act p) (eraseNoScan len act q)
  | act, .assign r e => .assign r (eraseE len act e)
  | act, .forN r k g b => .forN r k g (eraseNoScan len ((r, k) :: act) b)
  | _, p => p

/-- for i ulong 2: i = i + 2; x = get a i (len a = 2): the first index is 2, a trap 3. -/
def pWritten : Stmt :=
  .forN 0 2#64 none (.seq (.assign 0 (.op (fun x y => .ok (x + y)) (.reg 0) (.lit 2#64)))
    (.assign 1 (.get 0 (.reg 0) true)))

theorem written_traps : (exec lens 10 pWritten st0).code = some 3 := by decide
theorem written_rule_keeps : (exec lens 10 (erase lens [] pWritten) st0).code = some 3 := by decide
theorem written_without_scan : (exec lens 10 (eraseNoScan lens [] pWritten) st0).code = none := by decide

/-- A pass that erases any index inside an admitted loop (mutant reg). -/
def eraseAnyIx : List (Reg × Word) → Stmt → Stmt
  | act, .assign r (.get a ix true) => .assign r (.get a ix act.isEmpty)
  | act, .forN r k g b => .forN r k g (eraseAnyIx ((r, k) :: act) b)
  | _, p => p

/-- for i ulong 2: x = get a (i + 1): the second index is 2, a trap 3. -/
def pIdx : Stmt :=
  .forN 0 2#64 none (.assign 1 (.get 0 (.op (fun x y => .ok (x + y)) (.reg 0) (.lit 1#64)) true))

theorem idx_traps : (exec lens 10 pIdx st0).code = some 3 := by decide
theorem idx_rule_keeps : (exec lens 10 (erase lens [] pIdx) st0).code = some 3 := by decide
theorem idx_without_reg : (exec lens 10 (eraseAnyIx [] pIdx) st0).code = none := by decide

/-- The rule does erase: in for i ulong 2: x = get a i (len 2) the check is gone and the result is the
same normal end. -/
def pSum : Stmt := .forN 0 2#64 none (.assign 1 (.get 0 (.reg 0) true))
theorem sum_erased : erase lens [] pSum = .forN 0 2#64 none (.assign 1 (.get 0 (.reg 0) false)) := by
  rfl
theorem sum_same_end : (exec lens 10 (erase lens [] pSum) st0).code = none ∧
    (exec lens 10 pSum st0).code = none := by decide

end OmegaBce
