/* SPDX-License-Identifier: Apache-2.0
 * qrecord_dump.c -- REFERENCE-ONLY C dumper for tests/turing/qrecord_parity.sh. Linked against
 * the retired C src/turing/ty_qrecord.c at main commit 3f2c70dc5 to generate the committed
 * goldens (tests/turing/qrecord_golden) once; removed from the tree in the next commit.
 * tests/turing/qrecord_dump.om is the OM-2 side; both read the same corpus language (see
 * tests/turing/qrecord_parity.sh) and must print byte-identical output.
 */
#include "turing/ty_qrecord.h"
#include "turing/ty_math.h"
#include "sha256.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static tyqr_profile P;
static tyqr_world Wd;
static tyqr_freeze Fz;
static tyqr_gain Gn;
static ty_digest R[16];
static char mb[8192];
static size_t mlen;
static tyqr_repline RE[64];
static tyqr_devline DE[64];
static char lastpath[1024];
static int have_last;
static char line[20000];

static char *pstr(int k, int i, size_t *cap) {
    *cap = TYQR_VAL;
    if (k == 0) {
        char *t[12] = {P.profile, P.protocol, P.quantizer, P.edge_rule, P.floor_rule, P.families,
                       P.rider, P.lm_rule, P.baselines, P.thresholds_format, P.gen_version, P.unit};
        return (i >= 0 && i < 12) ? t[i] : NULL;
    }
    if (k == 1) {
        char *t[6] = {Wd.mode, Wd.parent_kind, Wd.cell, Wd.label, Wd.gen_version, Wd.traj_format};
        return (i >= 0 && i < 6) ? t[i] : NULL;
    }
    if (k == 2) {
        char *t[11] = {Fz.mode, Fz.artifact_kind, Fz.b2_emerging_label, Fz.bayes_plugin_check,
                       Fz.diag_fw_rate_ppm, Fz.lengthening_test, Fz.stability_test, Fz.calibration_extra,
                       Fz.base_commits, Fz.producer_tool, Fz.producer_model};
        return (i >= 0 && i < 11) ? t[i] : NULL;
    }
    if (k == 3) {
        char *t[9] = {Gn.mode, Gn.cell, Gn.gen_version, Gn.ladder_item, Gn.leak_flag, Gn.diag_warnings,
                      Gn.classification, Gn.status, Gn.unit};
        return (i >= 0 && i < 9) ? t[i] : NULL;
    }
    if (k == 4 && i == 0) {
        *cap = sizeof Fz.run_commit;
        return Fz.run_commit;
    }
    return NULL;
}

static ty_digest *pdig(int k, int i) {
    if (k == 0) {
        ty_digest *t[4] = {&P.spec, &P.packet, &P.cells, &P.thresholds};
        return (i >= 0 && i < 4) ? t[i] : NULL;
    }
    if (k == 1) {
        ty_digest *t[4] = {&Wd.qprofile, &Wd.qfreeze, &Wd.generator, &Wd.traj_manifest};
        return (i >= 0 && i < 4) ? t[i] : NULL;
    }
    if (k == 2) {
        if (i >= 6 && i < 14) return &Fz.lineage[i - 6];
        ty_digest *t[6] = {&Fz.artifact, &Fz.artifact_bin, &Fz.qprofile, &Fz.dev_manifest, &Fz.prompt_digest,
                           &Fz.transcript_digest};
        return (i >= 0 && i < 6) ? t[i] : NULL;
    }
    if (k == 3) {
        ty_digest *t[7] = {&Gn.qprofile, &Gn.qworld, &Gn.qfreeze, &Gn.baseline_artifact, &Gn.candidate,
                           &Gn.prd_b, &Gn.prd_m};
        return (i >= 0 && i < 7) ? t[i] : NULL;
    }
    return NULL;
}

static uint64_t *pu(int k, int i) {
    if (k == 0) {
        uint64_t *t[4] = {&P.kmax, &P.n_points, &P.split, &P.bootstrap_b};
        return (i >= 0 && i < 4) ? t[i] : NULL;
    }
    if (k == 1) {
        uint64_t *t[3] = {&Wd.block, &Wd.rep_first, &Wd.rep_count};
        return (i >= 0 && i < 3) ? t[i] : NULL;
    }
    if (k == 2) {
        uint64_t *t[2] = {&Fz.tree_dirty, &Fz.n_lineage};
        return (i >= 0 && i < 2) ? t[i] : NULL;
    }
    if (k == 3) {
        if (i >= 3 && i < 7) return &Gn.counts[i - 3];
        uint64_t *t[9] = {&Gn.baseline_opcode, &Gn.candidate_opcode, &Gn.official, NULL, NULL, NULL, NULL,
                          &Gn.floor_hits, &Gn.protocol_failures};
        return (i >= 0 && i < 9) ? t[i] : NULL;
    }
    return NULL;
}

static int64_t *pi(int k, int i) {
    if (k == 0) {
        int64_t *t[2] = {&P.delta_log2, &P.sd_min_log2};
        return (i >= 0 && i < 2) ? t[i] : NULL;
    }
    if (k == 3) {
        if (i >= 0 && i < 6) return &Gn.lengths[i];
        if (i >= 11 && i < 14) return &Gn.coverage[i - 11];
        int64_t *t[5] = {&Gn.t_ub, &Gn.t_lo_ub, &Gn.t_hi_ub, &Gn.numeric_bound_ub, &Gn.mc_err_ub};
        return (i >= 6 && i < 11) ? t[i - 6] : NULL;
    }
    return NULL;
}

static int hexv(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

/* hex token ("." = empty) into buf; returns byte count, or -1 */
static long unhex(const char *s, unsigned char *buf, size_t cap) {
    if (strcmp(s, ".") == 0) return 0;
    size_t n = strlen(s);
    if (n % 2 || n / 2 > cap) return -1;
    for (size_t i = 0; i < n / 2; ++i) {
        int a = hexv(s[2 * i]), b = hexv(s[2 * i + 1]);
        if (a < 0 || b < 0) return -1;
        buf[i] = (unsigned char)(a * 16 + b);
    }
    return (long)(n / 2);
}

static void phex(const ty_digest *d) {
    char h[65];
    ty_hex(d, h);
    fputs(h, stdout);
}

static void pbuf(void) {
    for (size_t i = 0; i < mlen; ++i) putchar(mb[i] == '\n' ? '|' : mb[i]);
}

static const char *dom(int k) {
    const char *t[4] = {TYQR_DOMAIN_PROFILE, TYQR_DOMAIN_WORLD, TYQR_DOMAIN_FREEZE, TYQR_DOMAIN_GAIN};
    return (k >= 0 && k < 4) ? t[k] : "x";
}

static void setstr(char *f, size_t cap, const unsigned char *b, size_t n) {
    memset(f, 0, cap);
    memcpy(f, b, n);
}

static void dirname_n(char *d, long n) {
    if (n <= 0) {
        strcpy(d, "qr_nodir");
        return;
    }
    strcpy(d, "qr_w");
    size_t l = 4;
    while ((long)l + 2 <= n) {
        d[l++] = '/';
        d[l++] = '.';
    }
    if ((long)l < n) d[l++] = '/';
    d[l] = 0;
}

int main(void) {
    unsigned char tmp[1100];
    while (fgets(line, sizeof line, stdin)) {
        size_t L = strlen(line);
        if (L && line[L - 1] == '\n') line[--L] = 0;
        if (L == 0 || line[0] == '#') continue;
        char c0[8] = {0};
        long a = 0, b = 0, c = 0, d = 0;
        char s1[1100] = {0};
        sscanf(line, "%7s", c0);
        if (!strcmp(c0, "Z")) {
            sscanf(line, "Z %ld", &a);
            if (a == 0) memset(&P, 0, sizeof P);
            if (a == 1) memset(&Wd, 0, sizeof Wd);
            if (a == 2) memset(&Fz, 0, sizeof Fz);
            if (a == 3) memset(&Gn, 0, sizeof Gn);
        } else if (!strcmp(c0, "S")) {
            sscanf(line, "S %ld %ld %1099s", &a, &b, s1);
            size_t cap;
            char *f = pstr((int)a, (int)b, &cap);
            long n = unhex(s1, tmp, cap);
            if (f && n >= 0) setstr(f, cap, tmp, (size_t)n);
        } else if (!strcmp(c0, "T")) {
            int off = 0;
            sscanf(line, "T %ld %ld %n", &a, &b, &off);
            size_t cap;
            char *f = pstr((int)a, (int)b, &cap);
            size_t n = strlen(line + off);
            if (f && off && n <= cap) setstr(f, cap, (const unsigned char *)line + off, n);
        } else if (!strcmp(c0, "U")) {
            char v[32] = {0};
            sscanf(line, "U %ld %ld %31s", &a, &b, v);
            uint64_t *p = pu((int)a, (int)b);
            if (p) *p = strtoull(v, NULL, 10);
        } else if (!strcmp(c0, "I")) {
            char v[32] = {0};
            sscanf(line, "I %ld %ld %31s", &a, &b, v);
            int64_t *p = pi((int)a, (int)b);
            if (p) *p = strtoll(v, NULL, 10);
        } else if (!strcmp(c0, "D")) {
            sscanf(line, "D %ld %ld %ld", &a, &b, &c);
            ty_digest *p = pdig((int)a, (int)b);
            if (p && c >= 0 && c < 16) *p = R[c];
        } else if (!strcmp(c0, "X")) {
            sscanf(line, "X %ld %1099s", &a, s1);
            if (a >= 0 && a < 16 && unhex(s1, tmp, 32) == 32) memcpy(R[a].b, tmp, 32);
        } else if (!strcmp(c0, "F")) {
            sscanf(line, "F %ld %ld", &a, &b);
            if (a >= 0 && a < 16) memset(R[a].b, (int)b, 32);
        } else if (!strcmp(c0, "P")) {
            sscanf(line, "P %ld", &a);
            printf("P %ld ", a);
            phex(&R[a & 15]);
            putchar('\n');
        } else if (!strcmp(c0, "G")) {
            sscanf(line, "G %ld %ld", &a, &b);
            ty_digest *o = &R[b & 15];
            int rc = a == 0 ? tyqr_profile_digest(&P, o)
                   : a == 1 ? tyqr_world_digest(&Wd, o)
                   : a == 2 ? tyqr_freeze_digest(&Fz, o)
                            : tyqr_gain_digest(&Gn, o);
            printf("G %ld %d", a, rc);
            if (rc == 0) {
                putchar(' ');
                phex(o);
            } else
                memset(o, 0, sizeof *o);
            putchar('\n');
        } else if (!strcmp(c0, "V")) {
            sscanf(line, "V %ld %ld", &a, &b);
            char why[256];
            const ty_digest *w = &R[b & 15];
            int rc = a == 0 ? tyqr_profile_verify(&P, w, why, sizeof why)
                   : a == 1 ? tyqr_world_verify(&Wd, w, why, sizeof why)
                   : a == 2 ? tyqr_freeze_verify(&Fz, w, why, sizeof why)
                            : tyqr_gain_verify(&Gn, w, why, sizeof why);
            printf("V %ld %d\n", a, rc);
        } else if (!strcmp(c0, "B")) {
            sscanf(line, "B %ld %ld %ld %ld", &a, &b, &c, &d);
            char why[256];
            int rc = tyqr_gain_bind(&Gn, &R[a & 15], &Wd, &R[b & 15], &Fz, &R[c & 15], &R[d & 15], why, sizeof why);
            printf("B %d\n", rc);
        } else if (!strcmp(c0, "W")) {
            sscanf(line, "W %ld %ld %ld", &a, &b, &c);
            char dir[1100], path[1024];
            dirname_n(dir, c);
            ty_digest *o = &R[b & 15];
            int rc = a == 0 ? tyqr_profile_write(dir, &P, o, path, sizeof path)
                   : a == 1 ? tyqr_world_write(dir, &Wd, o, path, sizeof path)
                   : a == 2 ? tyqr_freeze_write(dir, &Fz, o, path, sizeof path)
                            : tyqr_gain_write(dir, &Gn, o, path, sizeof path);
            printf("W %ld %d", a, rc);
            if (rc == 0 || rc == TYQR_E_EXISTS) {
                ty_digest fs;
                putchar(' ');
                phex(o);
                printf(" %zu ", strlen(path));
                if (ty_file_sha256(path, &fs) == 0) phex(&fs);
                else fputs("nofile", stdout);
                struct stat st;
                if (stat(path, &st) == 0) printf(" %u", (unsigned)(st.st_mode & 0777));
                else fputs(" nofile", stdout);
                strcpy(lastpath, path);
                have_last = 1;
            }
            putchar('\n');
        } else if (!strcmp(c0, "Y")) {
            sscanf(line, "Y %ld %ld", &a, &b);
            int rc = have_last ? tyqr_file_verify(lastpath, dom((int)a), &R[b & 15]) : -999;
            printf("Y %d\n", rc);
        } else if (!strcmp(c0, "YN")) {
            sscanf(line, "YN %1099s %ld %ld", s1, &a, &b);
            printf("YN %d\n", tyqr_file_verify(s1, dom((int)a), &R[b & 15]));
        } else if (!strcmp(c0, "M0")) {
            mlen = 0;
        } else if (!strcmp(c0, "MX")) {
            sscanf(line, "MX %1099s", s1);
            long n = unhex(s1, tmp, sizeof tmp);
            if (n > 0 && mlen + (size_t)n <= sizeof mb) {
                memcpy(mb + mlen, tmp, (size_t)n);
                mlen += (size_t)n;
            }
        } else if (!strcmp(c0, "MT")) {
            const char *t = line + 2;
            if (*t == ' ') ++t;
            size_t n = strlen(t);
            if (mlen + n + 1 <= sizeof mb) {
                memcpy(mb + mlen, t, n);
                mlen += n;
                mb[mlen++] = '\n';
            }
        } else if (!strcmp(c0, "MN")) {
            sscanf(line, "MN %ld %ld", &a, &b);
            for (long i = 0; i < a && mlen < sizeof mb; ++i) mb[mlen++] = (char)b;
        } else if (!strcmp(c0, "SD")) {
            sscanf(line, "SD %ld", &a);
            tyqr_sidecar_digest(mb, mlen, &R[a & 15]);
            fputs("SD ", stdout);
            phex(&R[a & 15]);
            putchar('\n');
        } else if (!strcmp(c0, "RE")) {
            char v[32] = {0};
            sscanf(line, "RE %ld %31s %ld", &a, v, &c);
            if (a >= 0 && a < 64) {
                RE[a].rep = strtoull(v, NULL, 10);
                RE[a].d = R[c & 15];
            }
        } else if (!strcmp(c0, "DE")) {
            char v[32] = {0};
            sscanf(line, "DE %ld %31s %ld %1099s", &a, v, &c, s1);
            if (a >= 0 && a < 64) {
                long n = unhex(s1, tmp, TYQR_CELL_MAX);
                if (n >= 0) {
                    memset(DE[a].cell, 0, sizeof DE[a].cell);
                    memcpy(DE[a].cell, tmp, (size_t)n);
                }
                DE[a].block = strtoull(v, NULL, 10);
                DE[a].d = R[c & 15];
            }
        } else if (!strcmp(c0, "RB") || !strcmp(c0, "DB")) {
            sscanf(line + 2, " %ld %ld", &a, &b);
            size_t len = 0;
            int rc = c0[0] == 'R' ? tyqr_repman_build(RE, (size_t)a, mb, (size_t)b, &len)
                                  : tyqr_devman_build(DE, (size_t)a, mb, (size_t)b, &len);
            mlen = rc == 0 ? len : 0;
            printf("%s %d %zu ", c0, rc, mlen);
            pbuf();
            putchar('\n');
        } else if (!strcmp(c0, "RP")) {
            sscanf(line, "RP %ld", &a);
            size_t n = 0;
            int rc = tyqr_repman_parse(mb, mlen, RE, (size_t)a, &n);
            printf("RP %d", rc);
            if (rc == 0) {
                printf(" %zu", n);
                for (size_t i = 0; i < n; ++i) {
                    printf(" %" PRIu64 "=", RE[i].rep);
                    phex(&RE[i].d);
                }
            }
            putchar('\n');
        } else if (!strcmp(c0, "DP")) {
            sscanf(line, "DP %ld", &a);
            size_t n = 0;
            int rc = tyqr_devman_parse(mb, mlen, DE, (size_t)a, &n);
            printf("DP %d", rc);
            if (rc == 0) {
                printf(" %zu", n);
                for (size_t i = 0; i < n; ++i) {
                    printf(" %s/%" PRIu64 "=", DE[i].cell, DE[i].block);
                    phex(&DE[i].d);
                }
            }
            putchar('\n');
        } else if (!strcmp(c0, "CT")) {
            printf("CT %d\n", tyqr_celltab_check(mb, mlen));
        } else if (!strcmp(c0, "TT")) {
            printf("TT %d\n", tyqr_thrtab_check(mb, mlen));
        } else {
            printf("? %s\n", c0);
        }
    }
    return 0;
}
