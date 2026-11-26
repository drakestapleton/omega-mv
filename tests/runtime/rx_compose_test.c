/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Drake Stapleton (AIEN / aien-dev)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * COMPOSITION-2 WP-B + WP-C: one World, one causal path, OLD-or-NEW.
 *
 * WP-B: every fault point on the path (before fork, candidate, before
 * commit, after validation, seal, reclaim, Cortex), each in process and as a
 * crashed child (_exit(77)); after reopen the World value, the durable
 * J-Space branch and the Cortex record agree on exactly OLD or exactly NEW,
 * losers are never recoverable, and the path still makes progress. Also: no
 * winner keeps OLD, a candidate subject that tries to write the state is
 * refused, a foreign machine identity is refused.
 *
 * WP-C: a World action becomes a Cortex claim / evidence / promotion with
 * provenance (World crumbs, branch ref, Skill digest); replay verifies the
 * journal and recall finds the record; a torn tail is repaired and the
 * composition completed; a corrupt middle is refused; branch identity
 * survives recording; a loser is never promoted.
 */
#include "rx_compose_fixture.h"
#include "omega_fs.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <pthread.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static int g_checks, g_fail;

#define CHECK(cond, ...) do {                                            \
        g_checks++;                                                      \
        if (!(cond)) {                                                   \
            g_fail++;                                                    \
            fprintf(stderr, "  FAIL %s:%d ", __FILE__, __LINE__);        \
            fprintf(stderr, __VA_ARGS__);                                \
            fputc('\n', stderr);                                         \
        }                                                                \
    } while (0)

static Fx g_fx;
static RxCompose g_c;               /* large: static */
static char g_base[128];

static int rm_one(const char *p, const struct stat *sb, int flag, struct FTW *ftw) {
    (void)sb; (void)flag; (void)ftw;
    return remove(p);
}
static void rmtree(const char *p) { nftw(p, rm_one, 16, FTW_DEPTH | FTW_PHYS); }

static void dir_for(char *out, size_t n, const char *name) {
    snprintf(out, n, "%s/%s", g_base, name);
    rmtree(out);
}

static void reset_c(void) {
    g_c.test.fault_point = RXC_FP_NONE;
    g_c.test.fault_crash = 0;
    g_c.test.fault_k = 0;
    g_c.test.rogue_candidate = 0;
}

static int ref_eq(JsBranchRef a, JsBranchRef b) { return a.id == b.id && a.gen == b.gen; }
static int noop_fn(RxCtx *x) { (void)x; return 0; }

/* Staged (never-committed) J-Space branches still held in memory. */
static uint32_t staged_branches(const JsSpace *s) {
    uint32_t n = 0;
    for (uint32_t i = 0; i < s->n_branches; i++) n += s->branches[i] && s->branches[i]->staged;
    return n;
}

/* Cleanup in process, before any close or reopen (L7-LIVING): every
 * candidate branch the run forked and did not commit is reclaimed and no
 * staged branch survives. A run that did not move the World also leaves
 * exactly one live branch (the state's) and promotes nothing. */
static void check_cleanup(const char *what, const RxcResult *o, uint32_t promotions_before) {
    int moved = !ref_eq(rx_compose_state(&g_c), o->old_ref);
    for (uint32_t k = 0; k < RXC_K; k++) {
        if (!o->cand_ref[k].id && !o->cand_ref[k].gen) continue;
        if (moved && ref_eq(o->cand_ref[k], rx_compose_state(&g_c))) continue;
        CHECK(js_branch_check(&g_c.js, o->cand_ref[k]) == JS_ERR_STALE,
              "%s: candidate %u reclaimed in process", what, k);
    }
    CHECK(staged_branches(&g_c.js) == 0, "%s: no staged branch survives (%u)", what,
          staged_branches(&g_c.js));
    if (!moved) {
        CHECK(fx_live_branches(&g_c.js) == 1, "%s: one live branch in process (%u)", what,
              fx_live_branches(&g_c.js));
        CHECK(fx_count(&g_c.cx, CX_K_PROMOTION, UINT64_MAX) == promotions_before,
              "%s: nothing promoted", what);
    }
}

/* Reference run: what OLD and NEW are for input 5 in a fresh directory. */
static struct {
    JsBranchRef old_ref, new_ref, cand[RXC_K];
    uint8_t old_dig[32], new_dig[32];
    uint64_t result;
} R;

static void t_reference(void) {
    printf("[*] reference run: fresh World, one goal, two alternatives, winner committed\n");
    char d[200];
    dir_for(d, sizeof d, "ref");
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "open ref");
    JsBranchRef s0 = rx_compose_state(&g_c);
    CHECK(js_branch_content_digest(&g_c.js, s0.id, R.old_dig) == JS_OK, "old digest");
    RxcResult o;
    CHECK(fx_run(&g_fx, &g_c, 5, &o) == RX_OK, "run");
    CHECK(o.outcome == RXC_OUT_COMMITTED, "committed (%d)", o.outcome);
    CHECK(o.n_alternatives == 2, "two alternatives (%u)", o.n_alternatives);
    CHECK(o.route[0].chosen.skill_id == FX_SKILL_A && o.route[1].chosen.skill_id == FX_SKILL_B,
          "rank order: A then B");
    CHECK(o.winner == 0 && o.result == 16, "winner A, result 16 (%u, %llu)", o.winner,
          (unsigned long long)o.result);
    CHECK(ref_eq(o.old_ref, s0), "old ref");
    CHECK(ref_eq(o.new_ref, o.cand_ref[0]), "new = candidate 0");
    CHECK(ref_eq(rx_compose_state(&g_c), o.new_ref), "World names NEW");
    CHECK(js_branch_check(&g_c.js, o.cand_ref[1]) == JS_ERR_STALE, "loser reclaimed");
    CHECK(js_branch_check(&g_c.js, s0) == JS_ERR_STALE, "superseded branch released");
    JsBranchInfo bi;
    CHECK(js_branch_info(&g_c.js, o.new_ref, &bi) == JS_OK && !bi.staged && bi.owner == 0,
          "winner sealed, no owner");
    CHECK(fx_live_branches(&g_c.js) == 1, "one live branch");
    check_cleanup("reference", &o, 0);   /* cleanup after success */
    R.old_ref = s0;
    R.new_ref = o.new_ref;
    R.cand[0] = o.cand_ref[0];
    R.cand[1] = o.cand_ref[1];
    memcpy(R.new_dig, o.winner_digest, 32);
    R.result = o.result;
    CHECK(memcmp(R.old_dig, R.new_dig, 32) != 0 && !ref_eq(R.old_ref, R.new_ref), "OLD and NEW differ");
    fx_close(&g_fx, &g_c);
    rmtree(d);
}

/* After reopen: World value, durable branch and Cortex agree on want_new. */
static void check_reopened(const char *what, int want_new, int point) {
    JsBranchRef want = want_new ? R.new_ref : R.old_ref;
    JsBranchRef s = rx_compose_state(&g_c);
    CHECK(ref_eq(s, want), "%s: World names %s (%u/%u)", what, want_new ? "NEW" : "OLD", s.id,
          s.gen);
    CHECK(ref_eq(g_c.recovered, s), "%s: recovered = World", what);
    const CxObject *ro = cx_get(&g_c.cx, g_c.recovered_record);
    if (ro) {
        const uint64_t *p = cx_payload(&g_c.cx, ro);
        CHECK(p[CX_WREC_FIELD0 + RXC_S_REF] == fx_pack(s), "%s: Cortex record names it", what);
        CHECK(ro->kind == (want_new ? CX_K_EXEC_COMMIT : CX_K_ENTITY_CREATED),
              "%s: Cortex record kind", what);
    } else {
        CHECK(0, "%s: no recovered record", what);
    }
    JsBranchInfo bi;
    CHECK(js_branch_info(&g_c.js, s, &bi) == JS_OK && !bi.staged, "%s: durable, sealed", what);
    CHECK(fx_live_branches(&g_c.js) == 1, "%s: exactly one durable branch (%u)", what,
          fx_live_branches(&g_c.js));
    uint8_t dg[32];
    CHECK(js_branch_content_digest(&g_c.js, s.id, dg) == JS_OK &&
          memcmp(dg, want_new ? R.new_dig : R.old_dig, 32) == 0, "%s: content is exactly %s",
          what, want_new ? "NEW" : "OLD");
    /* Losers (and NEW when OLD was kept) are never recoverable. */
    CHECK(js_branch_check(&g_c.js, R.cand[1]) == JS_ERR_STALE, "%s: loser gone", what);
    if (!want_new)
        CHECK(js_branch_check(&g_c.js, R.new_ref) == JS_ERR_STALE, "%s: NEW gone", what);
    RxObject so;
    rx_world_read(&g_c.w, g_c.state, &so);
    CHECK(so.field[RXC_S_RESULT] == (want_new ? R.result : 0), "%s: World result", what);
    CHECK(g_c.rolled_back == (point == RXC_FP_RECLAIM ? 1u : 0u), "%s: rollbacks %u", what,
          g_c.rolled_back);
    CHECK((g_c.recovered_completed > 0) == (point == RXC_FP_CORTEX), "%s: completed %u", what,
          g_c.recovered_completed);
    CHECK(fx_count(&g_c.cx, CX_K_PROMOTION, UINT64_MAX) == (want_new ? 1u : 0u),
          "%s: promotions", what);
}

static const char *fp_name[RXC_FP_END] = { "none", "before_fork", "candidate", "before_commit",
                                           "after_validation", "seal", "reclaim", "cortex" };

static void fault_case(int point, int crash, uint32_t k) {
    char d[200], what[64];
    snprintf(what, sizeof what, "%s/%s/k%u", fp_name[point], crash ? "crash" : "inproc", k);
    char leaf[64];
    snprintf(leaf, sizeof leaf, "f%d_%d_%u", point, crash, k);
    dir_for(d, sizeof d, leaf);
    int want_new = point == RXC_FP_CORTEX;
    if (crash) {
        fflush(NULL);
        pid_t pid = fork();
        if (pid == 0) {
            reset_c();
            g_c.test.fault_point = point;
            g_c.test.fault_crash = 1;
            g_c.test.fault_k = k;
            if (fx_open(&g_fx, &g_c, d, 1) != RX_OK) _exit(2);
            RxcResult o;
            fx_run(&g_fx, &g_c, 5, &o);
            _exit(3);   /* the fault did not fire */
        }
        int st = 0;
        waitpid(pid, &st, 0);
        CHECK(WIFEXITED(st) && WEXITSTATUS(st) == RXC_CRASH_EXIT, "%s: child crashed at point (%d)",
              what, WIFEXITED(st) ? WEXITSTATUS(st) : -1);
    } else {
        reset_c();
        g_c.test.fault_point = point;
        g_c.test.fault_k = k;
        CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "%s: open", what);
        RxcResult o;
        CHECK(fx_run(&g_fx, &g_c, 5, &o) == RX_OK, "%s: run", what);
        int want = point == RXC_FP_RECLAIM ? RXC_OUT_NOT_DURABLE
                 : point == RXC_FP_CORTEX  ? RXC_OUT_RECORD_FAILED : RXC_OUT_NOT_COMMITTED;
        CHECK(o.outcome == want, "%s: outcome %d want %d", what, o.outcome, want);
        CHECK(g_c.test.fault_hit, "%s: fault fired", what);
        check_cleanup(what, &o, 0);
        fx_close(&g_fx, &g_c);
    }
    reset_c();
    int rc = fx_open(&g_fx, &g_c, d, 1);
    CHECK(rc == RX_OK, "%s: reopen (%d)", what, rc);
    if (rc != RX_OK) return;
    check_reopened(what, want_new, point);
    /* The path still makes progress from what was recovered. */
    JsBranchRef before = rx_compose_state(&g_c);
    RxcResult o;
    CHECK(fx_run(&g_fx, &g_c, 6, &o) == RX_OK && o.outcome == RXC_OUT_COMMITTED,
          "%s: next goal commits (%d)", what, o.outcome);
    JsBranchInfo bi;
    CHECK(js_branch_info(&g_c.js, o.new_ref, &bi) == JS_OK && ref_eq(o.old_ref, before) &&
          o.result == 19, "%s: next goal built on the recovered state", what);
    fx_close(&g_fx, &g_c);
    /* And that is durable too. */
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK && ref_eq(rx_compose_state(&g_c), o.new_ref),
          "%s: second reopen names the next commit", what);
    fx_close(&g_fx, &g_c);
    rmtree(d);
}

static void t_faults(void) {
    printf("[*] fault points x {in process, crashed child}: exactly OLD or exactly NEW\n");
    for (int crash = 0; crash < 2; crash++)
        for (int p = RXC_FP_BEFORE_FORK; p < RXC_FP_END; p++) {
            fault_case(p, crash, 0);
            if (p == RXC_FP_BEFORE_FORK || p == RXC_FP_CANDIDATE) fault_case(p, crash, 1);
        }
}

static void t_no_winner(void) {
    printf("[*] no winner: both candidates break the contract, OLD kept, nothing promoted\n");
    char d[200];
    dir_for(d, sizeof d, "nowin");
    reset_c();
    fx_a_bad = fx_b_bad = 1;
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "open");
    RxcResult o;
    CHECK(fx_run(&g_fx, &g_c, 5, &o) == RX_OK && o.outcome == RXC_OUT_NO_WINNER, "no winner (%d)",
          o.outcome);
    fx_a_bad = fx_b_bad = 0;
    CHECK(o.winner == RXC_NONE && ref_eq(rx_compose_state(&g_c), R.old_ref), "OLD kept");
    CHECK(o.cx_promotion == 0 && fx_count(&g_c.cx, CX_K_PROMOTION, UINT64_MAX) == 0, "no promotion");
    CHECK(o.cx_candidate[0] && o.cx_candidate[1] && o.cx_evidence, "claims and evidence recorded");
    CHECK(o.cx_admission[0] && o.cx_admission[1], "both admitted as losers");
    const CxObject *ev = cx_get(&g_c.cx, o.cx_evidence);
    CHECK(ev && cx_payload(&g_c.cx, ev)[RXC_EP_WINNER] == RXC_NONE &&
          cx_payload(&g_c.cx, ev)[RXC_EP_PASSMASK] == 0, "evidence: no winner, nothing passed");
    for (uint32_t k = 0; k < RXC_K; k++)
        CHECK(js_branch_check(&g_c.js, o.cand_ref[k]) == JS_ERR_STALE, "candidate %u reclaimed", k);
    check_cleanup("no winner", &o, 0);
    fx_close(&g_fx, &g_c);
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "reopen");
    check_reopened("no winner", 0, RXC_FP_NONE);
    fx_close(&g_fx, &g_c);
    rmtree(d);
}

static void t_authority(void) {
    printf("[*] authority: a candidate cannot write the state; outside input needs its cap\n");
    char d[200];
    dir_for(d, sizeof d, "rogue");
    reset_c();
    g_c.test.rogue_candidate = 1;
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "open");
    RxcResult o;
    CHECK(fx_run(&g_fx, &g_c, 5, &o) == RX_OK && o.outcome == RXC_OUT_NOT_COMMITTED,
          "rogue run not committed (%d)", o.outcome);
    CHECK(ref_eq(rx_compose_state(&g_c), R.old_ref), "state untouched");
    check_cleanup("rogue", &o, 0);   /* cleanup after a refusal */
    /* The refusal is on the record. */
    uint32_t refused = 0;
    for (uint64_t id = 1; id <= g_c.cx.n; id++) {
        const CxObject *x = cx_get(&g_c.cx, id);
        if (!x || x->kind != CX_K_EXEC_FAILED ||
            cx_payload(&g_c.cx, x)[CX_WREC_REACTION] != g_c.rx_cand[0]) continue;
        if ((int64_t)cx_payload(&g_c.cx, x)[CX_WREC_REASON] == RX_ERR_WRITE_SET) refused++;
    }
    CHECK(refused >= 1, "EXEC_FAILED write-set refusal recorded (%u)", refused);
    /* A reaction under a candidate subject, holding only candidate rights,
     * that declares a state write is refused at registration. */
    RxReactionDesc r;
    memset(&r, 0, sizeof r);
    r.name = "rogue.state";
    r.faculty = RX_FACULTY_OMEGA;
    r.subject = RXC_SUBJ_CAND0;
    r.priority = RX_PRIO_FOREGROUND;
    r.triggers[r.n_triggers++] = (RxDep){ g_c.goal, RX_ALL_FIELDS };
    r.writes[r.n_writes++] = (RxDep){ g_c.state, RX_ALL_FIELDS };
    r.caps[r.n_caps++] = (RxCapNeed){ g_c.cap_cand[0][1], RXC_RES_STATE, RX_RIGHT_WRITE };
    r.fn = noop_fn;
    uint32_t id = 0;
    int rc = rx_world_add_reaction(&g_c.w, &r, &id);
    CHECK(rc == RX_ERR_AUTHORITY, "candidate cap cannot write state (%d)", rc);
    /* Outside input with a candidate's capability is refused. */
    RxMutation m = { g_c.goal, RXC_G_INPUT, 9 };
    CHECK(rx_world_publish_external(&g_c.w, g_c.cap_cand[0][0], &m, 1) < 0,
          "goal publish with a read cap refused");
    fx_close(&g_fx, &g_c);
    /* A foreign machine cannot open this composition. */
    AienMachineId other = fx_mid(2), mine = g_fx.self;
    g_fx.self = other;
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_ERR_IDENTITY, "foreign machine refused");
    g_fx.self = mine;
    rmtree(d);
}

/* ---- WP-C ---------------------------------------------------------------- */

static int words_eq(const uint64_t *w, const uint8_t d[32]) {
    for (int i = 0; i < 4; i++) {
        uint64_t v = 0;
        for (int b = 0; b < 8; b++) v |= (uint64_t)d[8 * i + b] << (8 * b);
        if (w[i] != v) return 0;
    }
    return 1;
}

static void t_cortex(void) {
    printf("[*] Cortex: provenance, replay + recall, torn tail, corrupt middle\n");
    char d[200];
    dir_for(d, sizeof d, "cortex");
    reset_c();
    fx_a_bad = 1;    /* A breaks the contract: B wins, A is the loser */
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "open");
    RxcResult o;
    CHECK(fx_run(&g_fx, &g_c, 5, &o) == RX_OK && o.outcome == RXC_OUT_COMMITTED, "commit (%d)",
          o.outcome);
    fx_a_bad = 0;
    CHECK(o.winner == 1, "B wins when A fails the contract (%u)", o.winner);
    CxStore *s = &g_c.cx;
    uint64_t wc = o.cx_candidate[1], lc = o.cx_candidate[0];
    const CxObject *cl = cx_get(s, wc);
    CHECK(cl && cl->kind == CX_K_CANDIDATE && cl->cls == CX_CLAIM, "winner claim");
    if (!cl) { fx_close(&g_fx, &g_c); return; }
    const uint64_t *cp = cx_payload(s, cl);
    CHECK(cp[RXC_CP_REF] == fx_pack(o.new_ref), "claim names the committed branch");
    CHECK((uint32_t)cp[RXC_CP_SKILL] == FX_SKILL_B && cp[RXC_CP_PASS] == 1, "claim: Skill B, passed");
    CHECK(words_eq(cp + RXC_CP_SKILLDIG0, g_fx.skills.skill[1].identity), "claim: Skill digest");
    CHECK(words_eq(cp + RXC_CP_DIGEST0, o.winner_digest), "claim: branch content digest");
    const CxObject *ck = cx_get(s, cl->links[0]), *g = cx_get(s, cl->links[1]);
    CHECK(ck && ck->kind == CX_K_EXEC_COMMIT && ck->subject == RXC_CX_SUBJECT(RXC_SLOT_CAND1),
          "claim -> candidate World record");
    CHECK(ck && cx_payload(s, ck)[CX_WREC_FIELD0 + RXC_C_REF] == fx_pack(o.new_ref),
          "World record carries the branch ref");
    CHECK(g && g->kind == CX_K_WORK_ACCEPTED && cx_payload(s, g)[CX_WREC_CRUMB] == o.goal_crumb,
          "claim -> goal record (crumb %llu)", (unsigned long long)o.goal_crumb);
    uint64_t prov[64];
    uint32_t np = cx_provenance(s, o.cx_promotion, prov, 64);
    int has_goal = 0, has_cand = 0;
    for (uint32_t i = 0; i < np; i++) {
        has_goal |= prov[i] == cl->links[1];
        has_cand |= prov[i] == cl->links[0];
    }
    CHECK(has_goal && has_cand, "promotion provenance reaches candidate and goal crumbs");
    const CxObject *pr = cx_get(s, o.cx_promotion), *ev = cx_get(s, o.cx_evidence);
    CHECK(pr && pr->kind == CX_K_PROMOTION && pr->links[0] == wc && pr->links[1] == o.cx_evidence,
          "promotion of the winner on the evidence");
    CHECK(ev && ev->protect == CX_PROT_VERIFY_EVIDENCE &&
          cx_payload(s, ev)[RXC_EP_VERIFIER] == RXC_SUBJ_AEGIS &&
          cx_payload(s, ev)[RXC_EP_PASSMASK] == 2, "evidence from the AEGIS verifier");
    const CxObject *sr = ev ? cx_get(s, ev->links[3]) : NULL;
    CHECK(sr && sr->kind == CX_K_EXEC_COMMIT &&
          cx_payload(s, sr)[CX_WREC_FIELD0 + RXC_S_REF] == fx_pack(o.new_ref),
          "evidence -> state World record naming the branch");
    /* The loser is admitted as a loser and never promoted. */
    const CxObject *la = cx_get(s, o.cx_admission[0]);
    CHECK(la && la->tag == RXC_ADMIT_LOSER && la->links[0] == lc, "loser admission");
    uint32_t lp = 0;
    for (uint64_t id = 1; id <= s->n; id++) {
        const CxObject *x = cx_get(s, id);
        if (x && x->kind == CX_K_PROMOTION && x->links[0] == lc) lp++;
    }
    CHECK(lp == 0, "loser claim never promoted");
    CHECK(cx_payload(s, cx_get(s, lc))[RXC_CP_PASS] == 0, "loser claim records the failure");
    uint64_t n_before = s->n;
    fx_close(&g_fx, &g_c);

    /* Replay: reopen verifies the chain; recall finds the claim, verified. */
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "reopen");
    s = &g_c.cx;
    CHECK(ref_eq(rx_compose_state(&g_c), o.new_ref), "branch identity survives recording");
    CHECK(cx_verify_chain(s) == CX_OK, "journal chain verifies");
    CxFilter f = { CX_CLAIM, CX_K_CANDIDATE, 0, 1 };
    CxRecord rec[16];
    uint32_t nr = cx_recall(s, RXC_CX_SUBJECT(RXC_SLOT_STATE), 0, UINT64_MAX, &f, rec, 16);
    int found = 0;
    for (uint32_t i = 0; i < nr; i++)
        if (rec[i].hdr.id == wc && rec[i].verified &&
            rec[i].payload[RXC_CP_REF] == fx_pack(o.new_ref)) found = 1;
    CHECK(found, "recall finds the verified winner claim (%u records)", nr);
    CHECK(fx_count(s, CX_K_PROMOTION, UINT64_MAX) == 1, "still one promotion");
    uint64_t n_reopen = s->n;
    CHECK(n_reopen > n_before, "reopen records the recovered entities");
    fx_close(&g_fx, &g_c);

    /* Torn tail: cut into the last record. Repair drops it; nothing else. */
    char p[256];
    snprintf(p, sizeof p, "%s/cortex.cx", d);
    struct stat sb;
    CHECK(stat(p, &sb) == 0 && truncate(p, sb.st_size - 3) == 0, "tear the tail");
    reset_c();
    int rc = fx_open(&g_fx, &g_c, d, 1);
    CHECK(rc == RX_OK, "torn tail repaired on open (%d)", rc);
    if (rc == RX_OK) {
        CHECK(ref_eq(rx_compose_state(&g_c), o.new_ref), "state after repair");
        CHECK(cx_verify_chain(&g_c.cx) == CX_OK, "chain after repair");
        fx_close(&g_fx, &g_c);
    }
    /* Admission cut short by a real crash: the process dies after the first
     * composition record and before the loser admission, so the checkpoint
     * still holds the previous anchor. Open completes the rest. A winning
     * composition is 5 records (2 claims, evidence, promotion, 1 loser
     * admission); one was written, so 4 are completed at open. */
    char d2[200];
    dir_for(d2, sizeof d2, "cortex2");
    fflush(NULL);
    pid_t pid = fork();
    if (pid == 0) {
        reset_c();
        g_c.test.fault_point = RXC_FP_CORTEX;
        g_c.test.fault_crash = 1;
        if (fx_open(&g_fx, &g_c, d2, 1) != RX_OK) _exit(2);
        RxcResult oc;
        fx_run(&g_fx, &g_c, 5, &oc);
        _exit(3);   /* the fault did not fire */
    }
    int cst = 0;
    waitpid(pid, &cst, 0);
    CHECK(WIFEXITED(cst) && WEXITSTATUS(cst) == RXC_CRASH_EXIT, "crash mid-admission (%d)",
          WIFEXITED(cst) ? WEXITSTATUS(cst) : -1);
    reset_c();
    int rc2 = fx_open(&g_fx, &g_c, d2, 1);
    CHECK(rc2 == RX_OK && g_c.recovered_completed == 4, "torn admission rewritten at open (%d, %u)",
          rc2, g_c.recovered_completed);
    if (rc2 == RX_OK) {
        CHECK(fx_count(&g_c.cx, CX_K_ADMISSION, RXC_ADMIT_LOSER) == 1 &&
              fx_count(&g_c.cx, CX_K_ADMISSION, RXC_ADMIT_RECOVERED) == 1, "completed + marked");
        fx_close(&g_fx, &g_c);
    }

    /* Artificial tear: a clean commit anchored the last admission, then the
     * record is cut away. That is durable data that vanished, so open refuses
     * (the checkpoint anchor is ahead of the journal). */
    char d3[200];
    dir_for(d3, sizeof d3, "cortex3");
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d3, 1) == RX_OK, "open 3");
    CHECK(fx_run(&g_fx, &g_c, 5, &o) == RX_OK && o.outcome == RXC_OUT_COMMITTED, "commit 3");
    CHECK(o.cx_admission[1] == g_c.cx.n, "loser admission is the last record");
    fx_close(&g_fx, &g_c);
    snprintf(p, sizeof p, "%s/cortex.cx", d3);
    CHECK(stat(p, &sb) == 0 && truncate(p, sb.st_size - 3) == 0, "tear the anchored admission");
    reset_c();
    rc = fx_open(&g_fx, &g_c, d3, 1);
    CHECK(rc == RX_ERR_REPLAY, "anchored record lost is refused (%d)", rc);
    if (rc == RX_OK) fx_close(&g_fx, &g_c);
    rmtree(d3);
    snprintf(p, sizeof p, "%s/cortex.cx", d2);

    /* Corrupt middle: one flipped byte in the body is refused, not repaired. */
    CHECK(stat(p, &sb) == 0, "stat");
    FILE *fp = fopen(p, "r+b");
    if (fp) {
        fseek(fp, sb.st_size / 2, SEEK_SET);
        int ch = fgetc(fp);
        fseek(fp, sb.st_size / 2, SEEK_SET);
        fputc(ch ^ 0x5A, fp);
        fclose(fp);
    }
    reset_c();
    rc = fx_open(&g_fx, &g_c, d2, 1);
    CHECK(rc == RX_ERR_REPLAY, "corrupt middle refused (%d)", rc);
    if (rc == RX_OK) fx_close(&g_fx, &g_c);
    rmtree(d);
    rmtree(d2);
}

/* The first goal's WORK_ACCEPTED record: claims and evidence of goal 1 carry it. */
static uint64_t first_goal(void) {
    for (uint64_t id = 1; id <= g_c.cx.n; id++) {
        const CxObject *o = cx_get(&g_c.cx, id);
        if (o && o->kind == CX_K_WORK_ACCEPTED && o->subject == RXC_CX_SUBJECT(RXC_SLOT_GOAL))
            return id;
    }
    return 0;
}

/* Goal 1's no-winner record is whole: two claims, one evidence, two losers. */
static void check_nowin_whole(const char *what, uint64_t G) {
    CHECK(G && fx_count(&g_c.cx, CX_K_CANDIDATE, G) == 2, "%s: goal 1 claims %u", what,
          fx_count(&g_c.cx, CX_K_CANDIDATE, G));
    CHECK(fx_count(&g_c.cx, CX_K_EVIDENCE_REF, G) == 1, "%s: goal 1 evidence", what);
    uint32_t losers = 0;
    for (uint64_t id = 1; id <= g_c.cx.n; id++) {
        const CxObject *o = cx_get(&g_c.cx, id);
        if (!o || o->kind != CX_K_ADMISSION || o->tag != RXC_ADMIT_LOSER) continue;
        const CxObject *cl = cx_get(&g_c.cx, o->links[0]);
        losers += cl && cl->kind == CX_K_CANDIDATE && cl->tag == G;
    }
    CHECK(losers == 2, "%s: goal 1 losers %u", what, losers);
}

static void t_pending(void) {
    printf("[*] incomplete records: completed before the next run, or at reopen\n");
    char d[200];
    RxcResult o;

    /* (a) no winner, record fails in process; the next run completes it first. */
    dir_for(d, sizeof d, "pend_nowin");
    reset_c();
    fx_a_bad = fx_b_bad = 1;
    g_c.test.fault_point = RXC_FP_CORTEX;
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "a: open");
    CHECK(fx_run(&g_fx, &g_c, 5, &o) == RX_OK && o.outcome == RXC_OUT_RECORD_FAILED && g_c.test.fault_hit,
          "a: no-winner record failed (%d)", o.outcome);
    fx_a_bad = fx_b_bad = 0;
    uint64_t G1 = first_goal();
    CHECK(fx_count(&g_c.cx, CX_K_CANDIDATE, G1) == 1, "a: record partial");
    CHECK(fx_run(&g_fx, &g_c, 6, &o) == RX_OK && o.outcome == RXC_OUT_COMMITTED && o.result == 19,
          "a: next run commits (%d)", o.outcome);
    CHECK(o.prior_completed == 4, "a: completed first %u", o.prior_completed);
    check_nowin_whole("a", G1);
    CHECK(fx_count(&g_c.cx, CX_K_PROMOTION, UINT64_MAX) == 1, "a: only goal 2 promoted");
    JsBranchRef nw = o.new_ref;
    fx_close(&g_fx, &g_c);
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK && g_c.recovered_completed == 0 &&
          g_c.rolled_back == 0 && ref_eq(rx_compose_state(&g_c), nw), "a: reopen clean (%u)",
          g_c.recovered_completed);
    fx_close(&g_fx, &g_c);
    rmtree(d);

    /* (b) no winner, crash inside the record; reopen completes it. */
    dir_for(d, sizeof d, "pend_nowin_crash");
    fflush(NULL);
    pid_t pid = fork();
    if (pid == 0) {
        reset_c();
        fx_a_bad = fx_b_bad = 1;
        g_c.test.fault_point = RXC_FP_CORTEX;
        g_c.test.fault_crash = 1;
        if (fx_open(&g_fx, &g_c, d, 1) != RX_OK) _exit(2);
        fx_run(&g_fx, &g_c, 5, &o);
        _exit(3);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK(WIFEXITED(st) && WEXITSTATUS(st) == RXC_CRASH_EXIT, "b: child crashed in the record (%d)",
          WIFEXITED(st) ? WEXITSTATUS(st) : -1);
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "b: reopen");
    CHECK(g_c.recovered_completed > 0 && g_c.rolled_back == 0, "b: completed %u at open",
          g_c.recovered_completed);
    check_nowin_whole("b", first_goal());
    CHECK(fx_count(&g_c.cx, CX_K_PROMOTION, UINT64_MAX) == 0, "b: nothing promoted");
    CHECK(fx_count(&g_c.cx, CX_K_ADMISSION, RXC_ADMIT_RECOVERED) == 1, "b: one recovered admission");
    const CxObject *ro = cx_get(&g_c.cx, g_c.recovered_record);
    CHECK(ro && ro->kind == CX_K_ENTITY_CREATED, "b: OLD kept");
    fx_close(&g_fx, &g_c);
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK && g_c.recovered_completed == 0, "b: second reopen clean");
    fx_close(&g_fx, &g_c);
    rmtree(d);

    /* (c) winner, record fails in process; the next run completes it first. */
    dir_for(d, sizeof d, "pend_win");
    reset_c();
    g_c.test.fault_point = RXC_FP_CORTEX;
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "c: open");
    CHECK(fx_run(&g_fx, &g_c, 5, &o) == RX_OK && o.outcome == RXC_OUT_RECORD_FAILED,
          "c: record failed (%d)", o.outcome);
    CHECK(fx_count(&g_c.cx, CX_K_PROMOTION, UINT64_MAX) == 0, "c: winner not yet promoted");
    CHECK(fx_run(&g_fx, &g_c, 6, &o) == RX_OK && o.outcome == RXC_OUT_COMMITTED && o.result == 19,
          "c: next run commits (%d)", o.outcome);
    CHECK(o.prior_completed > 0, "c: completed first %u", o.prior_completed);
    CHECK(fx_count(&g_c.cx, CX_K_PROMOTION, UINT64_MAX) == 2, "c: both winners promoted");
    CHECK(fx_live_branches(&g_c.js) == 1, "c: superseded branches released (%u)",
          fx_live_branches(&g_c.js));
    nw = o.new_ref;
    fx_close(&g_fx, &g_c);
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK && g_c.recovered_completed == 0 &&
          ref_eq(rx_compose_state(&g_c), nw), "c: reopen clean (%u)", g_c.recovered_completed);
    fx_close(&g_fx, &g_c);
    rmtree(d);

    /* (d) NOT_DURABLE: no further run until reopened. */
    dir_for(d, sizeof d, "pend_notdurable");
    reset_c();
    g_c.test.fault_point = RXC_FP_RECLAIM;
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "d: open");
    CHECK(fx_run(&g_fx, &g_c, 5, &o) == RX_OK && o.outcome == RXC_OUT_NOT_DURABLE,
          "d: not durable (%d)", o.outcome);
    CHECK(fx_run(&g_fx, &g_c, 6, &o) == RX_ERR_REPLAY, "d: next run refused");
    fx_close(&g_fx, &g_c);
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK && g_c.rolled_back == 1, "d: reopen rolls back");
    CHECK(fx_run(&g_fx, &g_c, 6, &o) == RX_OK && o.outcome == RXC_OUT_COMMITTED, "d: then commits");
    fx_close(&g_fx, &g_c);
    rmtree(d);

    /* (e) an earlier durable winner whose record was never completed, under a
     * newer commit (pending bypassed): reopen completes the older one too. */
    dir_for(d, sizeof d, "pend_older");
    reset_c();
    g_c.test.fault_point = RXC_FP_CORTEX;
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "e: open");
    CHECK(fx_run(&g_fx, &g_c, 5, &o) == RX_OK && o.outcome == RXC_OUT_RECORD_FAILED,
          "e: record failed (%d)", o.outcome);
    g_c.pending = 0;   /* simulate a writer that did not complete it */
    CHECK(fx_run(&g_fx, &g_c, 6, &o) == RX_OK && o.outcome == RXC_OUT_COMMITTED,
          "e: newer commit (%d)", o.outcome);
    CHECK(fx_count(&g_c.cx, CX_K_PROMOTION, UINT64_MAX) == 1, "e: older winner unpromoted");
    nw = o.new_ref;
    fx_close(&g_fx, &g_c);
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, d, 1) == RX_OK, "e: reopen");
    CHECK(g_c.recovered_completed > 0 && g_c.rolled_back == 0 && ref_eq(rx_compose_state(&g_c), nw),
          "e: older record completed at open (%u)", g_c.recovered_completed);
    CHECK(fx_count(&g_c.cx, CX_K_PROMOTION, UINT64_MAX) == 2, "e: older winner promoted");
    CHECK(fx_live_branches(&g_c.js) == 1, "e: one durable branch");
    fx_close(&g_fx, &g_c);
    rmtree(d);
}

/* A dir refused by src/omega_path_check.h is an argument error and creates nothing. */
static void t_refused_dir(void) {
    printf("[*] refused dir: RX_ERR_ARG, nothing created\n");
    char bad[240];
    snprintf(bad, sizeof bad, "%s/refused dir", g_base);
    reset_c();
    int rc = fx_open(&g_fx, &g_c, bad, 1);
    CHECK(rc == RX_ERR_ARG, "refused dir -> RX_ERR_ARG (%d)", rc);
    CHECK(access(bad, F_OK) != 0, "refused dir not created");
}

static void t_symlink_confinement(void) {
    printf("[*] symlink confinement: roots and identity files are refused\n");
    char real[240], link[240], identity[280], victim[280], got[5] = { 0 };
    dir_for(real, sizeof real, "symlink_real");
    dir_for(link, sizeof link, "symlink_root");
    CHECK(mkdir(real, 0700) == 0 && symlink(real, link) == 0, "symlink root setup");
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, link, 1) == RX_ERR_ARG, "symlink root was accepted");
    snprintf(identity, sizeof identity, "%s/machine.id", real);
    CHECK(access(identity, F_OK) != 0, "symlink root target was modified");
    unlink(link);
    rmtree(real);

    dir_for(real, sizeof real, "symlink_identity");
    CHECK(mkdir(real, 0700) == 0, "identity directory setup");
    snprintf(victim, sizeof victim, "%s/victim", real);
    FILE *f = fopen(victim, "wb");
    CHECK(f && fwrite("SAFE", 1, 4, f) == 4, "identity victim setup");
    if (f) fclose(f);
    snprintf(identity, sizeof identity, "%s/machine.id", real);
    CHECK(symlink(victim, identity) == 0, "identity symlink setup");
    reset_c();
    CHECK(fx_open(&g_fx, &g_c, real, 1) == RX_ERR_IDENTITY, "symlink identity was accepted");
    f = fopen(victim, "rb");
    CHECK(f && fread(got, 1, 4, f) == 4 && memcmp(got, "SAFE", 4) == 0,
          "identity symlink target was modified");
    if (f) fclose(f);
    rmtree(real);
}

typedef struct {
    Fx fx;
    RxCompose c;
    const char *dir;
    atomic_int *ready;
    int rc;
} OpenRaceWorker;

static OpenRaceWorker g_race[2];

static void *open_race_thread(void *arg) {
    OpenRaceWorker *w = arg;
    atomic_fetch_add(w->ready, 1);
    while (atomic_load(w->ready) < 2) {
        /* spin briefly so both threads race on open_home */
    }
    w->rc = rx_compose_open(&w->c, w->dir, &w->fx.self, FX_SESSION, &w->fx.router,
                            fx_contract, w->fx.admin, w->fx.view, 1);
    return NULL;
}

static int has_stray_identity_tmp(const char *dir) {
    DIR *dp = opendir(dir);
    if (!dp) return 1;
    int stray = 0;
    struct dirent *e;
    while ((e = readdir(dp))) {
        if (strncmp(e->d_name, "machine.id.tmp.", 15) == 0) {
            stray = 1;
            break;
        }
    }
    closedir(dp);
    return stray;
}

static void t_concurrent_first_open_identity(void) {
    printf("[*] concurrent first-open: atomic non-replacing identity install\n");
    char d[240];
    dir_for(d, sizeof d, "create_atomic");
    int dfd = omega_fs_root_open(d, 1, 0700);
    CHECK(dfd >= 0, "open create_atomic dir");
    if (dfd >= 0) {
        AienMachineId m1 = fx_mid(21), m2 = fx_mid(22), got;
        CHECK(aien_mid_create_at(dfd, "machine.id", &m1) == AIEN_MID_OK,
              "first create succeeds");
        CHECK(aien_mid_create_at(dfd, "machine.id", &m2) == AIEN_MID_E_EXISTS,
              "second non-replacing create returns AIEN_MID_E_EXISTS");
        CHECK(aien_mid_load_at(dfd, "machine.id", &got) == AIEN_MID_OK &&
                  aien_mid_equal(&got, &m1),
              "winning identity preserved on EEXIST");

        char sym[280], target[280];
        snprintf(sym, sizeof sym, "%s/sym.id", d);
        snprintf(target, sizeof target, "%s/absent_target", d);
        CHECK(symlink(target, sym) == 0, "create dangling sym.id");
        CHECK(aien_mid_create_at(dfd, "sym.id", &m1) == AIEN_MID_E_EXISTS,
              "dangling symlink refused with AIEN_MID_E_EXISTS");
        CHECK(access(target, F_OK) != 0, "dangling symlink target untouched");
        CHECK(!has_stray_identity_tmp(d), "no stray temp files after create_at checks");
        close(dfd);
    }
    rmtree(d);

    /* Case A: two threads race to initialize the same fresh home with distinct identities. */
    for (int round = 0; round < 16; round++) {
        char rd[240], name[64];
        snprintf(name, sizeof name, "race_diff_%d", round);
        dir_for(rd, sizeof rd, name);
        CHECK(mkdir(rd, 0700) == 0, "race diff %d mkdir", round);

        memset(g_race, 0, sizeof g_race);
        AienMachineId m1 = fx_mid((uint8_t)(30 + round * 2));
        AienMachineId m2 = fx_mid((uint8_t)(31 + round * 2));
        atomic_int ready = 0;
        CHECK(fx_init_for(&g_race[0].fx, &m1) == 0 && fx_init_for(&g_race[1].fx, &m2) == 0,
              "race diff %d fx_init_for", round);
        CHECK(aienos_cap_start(&g_race[0].fx.admin, &g_race[0].fx.view) == 0 &&
                  aienos_cap_start(&g_race[1].fx.admin, &g_race[1].fx.view) == 0,
              "race diff %d aienos_cap_start", round);
        g_race[0].dir = rd;
        g_race[1].dir = rd;
        g_race[0].ready = &ready;
        g_race[1].ready = &ready;

        pthread_t th[2];
        CHECK(pthread_create(&th[0], NULL, open_race_thread, &g_race[0]) == 0, "pthread 0");
        CHECK(pthread_create(&th[1], NULL, open_race_thread, &g_race[1]) == 0, "pthread 1");
        pthread_join(th[0], NULL);
        pthread_join(th[1], NULL);

        int one_ok_one_id = (g_race[0].rc == RX_OK && g_race[1].rc == RX_ERR_IDENTITY) ||
                            (g_race[1].rc == RX_OK && g_race[0].rc == RX_ERR_IDENTITY);
        CHECK(one_ok_one_id, "race diff %d: rc0=%d rc1=%d", round, g_race[0].rc, g_race[1].rc);

        int win = g_race[0].rc == RX_OK ? 0 : 1;
        int lose = 1 - win;
        for (int i = 0; i < 2; i++) {
            if (g_race[i].rc == RX_OK) rx_compose_close(&g_race[i].c);
            aienos_cap_stop(g_race[i].fx.admin, g_race[i].fx.view);
            fx_free(&g_race[i].fx);
        }

        int vfd = omega_fs_root_open(rd, 0, 0);
        AienMachineId stored;
        CHECK(vfd >= 0 && aien_mid_load_at(vfd, "machine.id", &stored) == AIEN_MID_OK &&
                  aien_mid_equal(&stored, win == 0 ? &m1 : &m2),
              "race diff %d: persisted machine.id matches winner", round);
        if (vfd >= 0) close(vfd);

        Fx vf;
        static RxCompose vc;
        CHECK(fx_init_for(&vf, win == 0 ? &m1 : &m2) == 0, "winner fx_init");
        CHECK(fx_open(&vf, &vc, rd, 1) == RX_OK, "race diff %d: winner reopens", round);
        fx_close(&vf, &vc);
        fx_free(&vf);

        CHECK(fx_init_for(&vf, lose == 0 ? &m1 : &m2) == 0, "loser fx_init");
        CHECK(fx_open(&vf, &vc, rd, 1) == RX_ERR_IDENTITY, "race diff %d: loser still refused",
              round);
        fx_free(&vf);

        CHECK(!has_stray_identity_tmp(rd), "race diff %d: no stray temp files", round);
        rmtree(rd);
    }

    /* Case B: same identity racing on fresh home never fails with RX_ERR_IDENTITY. */
    for (int round = 0; round < 8; round++) {
        char rd[240], name[64];
        snprintf(name, sizeof name, "race_same_%d", round);
        dir_for(rd, sizeof rd, name);
        CHECK(mkdir(rd, 0700) == 0, "race same %d mkdir", round);

        memset(g_race, 0, sizeof g_race);
        AienMachineId m1 = fx_mid((uint8_t)(80 + round));
        atomic_int ready = 0;
        CHECK(fx_init_for(&g_race[0].fx, &m1) == 0 && fx_init_for(&g_race[1].fx, &m1) == 0,
              "race same %d fx_init_for", round);
        CHECK(aienos_cap_start(&g_race[0].fx.admin, &g_race[0].fx.view) == 0 &&
                  aienos_cap_start(&g_race[1].fx.admin, &g_race[1].fx.view) == 0,
              "race same %d aienos_cap_start", round);
        g_race[0].dir = rd;
        g_race[1].dir = rd;
        g_race[0].ready = &ready;
        g_race[1].ready = &ready;

        pthread_t th[2];
        CHECK(pthread_create(&th[0], NULL, open_race_thread, &g_race[0]) == 0, "pthread 0");
        CHECK(pthread_create(&th[1], NULL, open_race_thread, &g_race[1]) == 0, "pthread 1");
        pthread_join(th[0], NULL);
        pthread_join(th[1], NULL);

        int ok_and_lock = (g_race[0].rc == RX_OK && g_race[1].rc == RX_ERR_REPLAY) ||
                          (g_race[1].rc == RX_OK && g_race[0].rc == RX_ERR_REPLAY);
        CHECK(ok_and_lock, "race same %d: rc0=%d rc1=%d", round, g_race[0].rc, g_race[1].rc);
        for (int i = 0; i < 2; i++) {
            if (g_race[i].rc == RX_OK) rx_compose_close(&g_race[i].c);
            aienos_cap_stop(g_race[i].fx.admin, g_race[i].fx.view);
            fx_free(&g_race[i].fx);
        }
        CHECK(!has_stray_identity_tmp(rd), "race same %d: no stray temp files", round);
        rmtree(rd);
    }
}

int main(void) {
    snprintf(g_base, sizeof g_base, "/tmp/rx_compose_test.XXXXXX");
    if (!mkdtemp(g_base)) { perror("mkdtemp"); return 1; }
    if (fx_init(&g_fx) != 0) { fprintf(stderr, "fixture init failed\n"); return 1; }
    t_reference();
    t_faults();
    t_no_winner();
    t_authority();
    t_cortex();
    t_pending();
    t_refused_dir();
    t_symlink_confinement();
    t_concurrent_first_open_identity();
    fx_free(&g_fx);
    rmtree(g_base);
    printf("%s: %d checks, %d failed\n", g_fail ? "FAIL" : "PASS", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
