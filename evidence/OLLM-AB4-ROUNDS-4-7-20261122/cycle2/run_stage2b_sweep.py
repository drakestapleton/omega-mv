import os, sys, subprocess, tempfile, hashlib
from concurrent.futures import ThreadPoolExecutor

camp = "/home/drakestapleton/work/ollm-helix-rlvr-20261121"
ab4 = f"{camp}/ab4_cycle2"
ollm = f"{camp}/bin/ollm"
omc = f"{camp}/bin/omc"
loop_ck = f"{camp}/ckpt/loop_r3.ck"
merges = "/home/drakestapleton/work/ollm-loop-20261121/data/omega4096.bin"
lsd = f"{camp}/ab4_cycle1/loop_spec"
strands = [
    f"{lsd}/S1_arith.sp",
    f"{lsd}/S2_fold.sp",
    f"{lsd}/S3_rewrite.sp",
    f"{lsd}/S4_repair.sp",
]
K = 4
TEMP = "700"

# Load oracles
oracles = {}
with open(f"{ab4}/stage0/oracles_108.tsv") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 5:
            oracles[parts[0]] = (parts[1], parts[2], parts[3], parts[4].replace("\\n", "\n"))

# Load accepted live q36-35b Architect plans
plans = []
with open(f"{ab4}/stage1/plans_108.tsv") as f:
    next(f)
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 5 and parts[0] in oracles:
            plans.append((parts[0], parts[1], parts[3], parts[4]))

print(f"SWEEP_CONFIG tasks={len(plans)} strands=4 K={K} temp={TEMP} total_candidates={len(plans)*4*K}", flush=True)

def eval_one_sample(tid, sig, desc, chk, s_idx, k_idx):
    prompt = f"note {desc}\nfn solve {sig}\n"
    seed = str(1000 + s_idx * 100 + k_idx)
    sp = strands[s_idx]
    r = subprocess.run(
        [ollm, "spsamp", loop_ck, sp, "64", TEMP, prompt, seed, merges],
        capture_output=True, timeout=60
    )
    if r.returncode != 0:
        return (0, 0, 0, 16, "")
    body = r.stdout.decode("utf-8", errors="ignore").replace("\x00", "")
    # Extract up to matching end
    lines = body.splitlines()
    blk = []
    depth = 1
    closed = False
    for ln in lines:
        s = ln.strip()
        blk.append(ln)
        if s.startswith("if ") or s.startswith("while ") or s.startswith("for "):
            depth += 1
        elif s == "end":
            depth -= 1
            if depth == 0:
                closed = True
                break
    if not closed:
        return (0, 0, 0, 15, body)
    fn_code = f"fn solve {sig}\n" + "\n".join(blk)
    full_src = f"om2\n{fn_code}\nfn main to int\n{chk}\nend\n"
    cr = subprocess.run([omc], input=full_src.encode(), capture_output=True, timeout=10)
    if cr.returncode != 0:
        err_s = cr.stderr.decode("utf-8", errors="ignore")
        ec = 16
        for tok in err_s.split():
            if tok.isdigit():
                ec = int(tok)
        return (0, 0, 0, ec, fn_code)
    fd, bin_p = tempfile.mkstemp(suffix=".bin")
    os.write(fd, cr.stdout)
    os.close(fd)
    src_p = ""
    try:

        os.chmod(bin_p, 0o755)
        try:
            import time
            for _tr in range(3):
                try:
                    er = subprocess.run([bin_p], timeout=3)
                    break
                except OSError:
                    time.sleep(0.05)
            rc = er.returncode
        except subprocess.TimeoutExpired:
            rc = 124
        if rc == 0:
            return (1, 1, 1, 0, fn_code)
        # Hash the wrong behavior (rc + normalized code) so identical bugs hash same, divergent bugs differ
        h = int(hashlib.sha256(f"{rc}:{fn_code}".encode()).hexdigest()[:8], 16) % 900000 + 10
        return (1, 0, h, 0, fn_code)
    finally:
        pass
        if os.path.exists(bin_p): os.unlink(bin_p)

def eval_task(item):
    tid, fam, desc, plan = item
    _, sig, _, chk = oracles[tid]
    strand_res = []
    wins = set()
    fails = []
    tot_comp = 0
    tot_pass = 0
    for s_idx in range(4):
        best_c, best_p, best_h, best_e = 0, 0, 0, 16
        for k_idx in range(K):
            c, p, h, e, code = eval_one_sample(tid, sig, desc, chk, s_idx, k_idx)
            tot_comp += c
            tot_pass += p
            if p == 1:
                wins.add(code)
                best_c, best_p, best_h, best_e = 1, 1, 1, 0
            elif c == 1 and best_p == 0:
                if best_c == 0:
                    best_c, best_h, best_e = 1, h, 0
                if code:
                    fails.append((s_idx+1, "wrong_exec", code))
            elif best_c == 0:
                best_e = e
                if code:
                    fails.append((s_idx+1, f"omc_err_{e}", code))
        strand_res.append((best_c, best_p, best_h, best_e))
    return (tid, fam, desc, plan, strand_res, list(wins), fails, tot_comp, tot_pass)

results = []
with ThreadPoolExecutor(max_workers=16) as ex:
    for res in ex.map(eval_task, plans):
        results.append(res)

matrix_lines = ["task_id\tfamily\tc1\tp1\th1\te1\tc2\tp2\th2\te2\tc3\tp3\th3\te3\tc4\tp4\th4\te4"]
direct_traces = []
align_traces = []
repair_traces = []
tasks_solved = 0
total_comp = 0
total_pass = 0
total_cands = len(results) * 4 * K

for tid, fam, desc, plan, sres, wins, fails, tc, tp in results:
    total_comp += tc
    total_pass += tp
    cols = [tid, fam]
    for c, p, h, e in sres:
        cols.extend([str(c), str(p), str(h), str(e)])
    matrix_lines.append("\t".join(cols))
    if wins:
        tasks_solved += 1
        for wcode in wins:
            direct_traces.append(f"note {desc}\n{wcode}\n")
            align_traces.append(f"note ARCH_PLAN: {plan}\n{wcode}\n")
        gold = wins[0]
        for s_num, err_tag, bad_code in fails[:4]:
            repair_traces.append(f"note repair ({err_tag}): {desc}\n{gold}\n")

open(f"{ab4}/stage3/c2_matrix.tsv", "w").write("\n".join(matrix_lines) + "\n")
open(f"{ab4}/stage5/direct_c2.om", "wb").write(b"\x00".join(t.encode() for t in direct_traces) + (b"\x00" if direct_traces else b""))
open(f"{ab4}/stage5/align_c2.om", "wb").write(b"\x00".join(t.encode() for t in align_traces) + (b"\x00" if align_traces else b""))
open(f"{ab4}/stage5/repair_c2.om", "wb").write(b"\x00".join(t.encode() for t in repair_traces) + (b"\x00" if repair_traces else b""))

print(f"C2_SWEEP_SUMMARY tasks={len(results)} tasks_solved={tasks_solved} unique_gold_traces={len(direct_traces)} repair_pairs={len(repair_traces)} cand_compiled={total_comp}/{total_cands} ({100.0*total_comp/max(1,total_cands):.1f}%) cand_pass={total_pass}/{total_cands}", flush=True)
