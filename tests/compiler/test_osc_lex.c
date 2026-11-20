/* SPDX-License-Identifier: Apache-2.0 */
/* Run the production entry point and the independent C lexer on identical
 * length-delimited bytes. Compare partial output and guard slots on errors. */
#include "osc_lex.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int osc_lex_reference(const char *, size_t, OscToken *, uint32_t, uint32_t *, OscDiag *);

static unsigned cases;

static void compare(const char *label, const char *src, size_t len, uint32_t cap)
{
    size_t bytes = (cap + (size_t)1) * sizeof(OscToken);
    OscToken *want = malloc(bytes), *got = malloc(bytes);
    if (!want || !got) abort();
    memset(want, 0xa5, bytes);
    memset(got, 0xa5, bytes);
    uint32_t nw = UINT32_MAX, ng = UINT32_MAX;
    OscDiag dw, dg;
    memset(&dw, 0xa5, sizeof dw);
    memset(&dg, 0xa5, sizeof dg);
    int rw = osc_lex_reference(src, len, want, cap, &nw, &dw);
    int rg = osc_lex(src, len, got, cap, &ng, &dg);
    if (rw != rg || nw != ng || memcmp(&dw, &dg, sizeof dw) || memcmp(want, got, bytes)) {
        fprintf(stderr, "FAIL lexer case %u (%s) len=%zu cap=%u, return %d/%d count %u/%u\n",
                cases, label, len, cap, rw, rg, nw, ng);
        if (rw) fprintf(stderr, "C diagnostic: %u:%u %s\n", dw.line, dw.col, dw.message);
        if (rg) fprintf(stderr, "Omega diagnostic: %u:%u %s\n", dg.line, dg.col, dg.message);
        for (uint32_t i = 0; i <= cap; ++i) {
            if (memcmp(&want[i], &got[i], sizeof *want)) {
                fprintf(stderr, "first differing token %u: kind %u/%u, offset %u/%u, width %u/%u\n",
                        i, want[i].kind, got[i].kind, want[i].off, got[i].off, want[i].len, got[i].len);
                break;
            }
        }
        exit(1);
    }
    ++cases;
    free(want);
    free(got);
}

static void file_case(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f || fseek(f, 0, SEEK_END)) { perror(path); exit(1); }
    long len = ftell(f);
    if (len < 0 || fseek(f, 0, SEEK_SET)) { perror(path); exit(1); }
    char *src = malloc((size_t)len + 1);
    if (!src || fread(src, 1, (size_t)len, f) != (size_t)len) abort();
    fclose(f);
    compare(path, src, (size_t)len, len < OSC_LEX_MAX_TOKENS ? (uint32_t)len + 1 : OSC_LEX_MAX_TOKENS);
    free(src);
}

int main(int argc, char **argv)
{
    static const char *const inputs[] = {
        "", " \r\t\n\n", "//", "/**/", "a/* first\nsecond **/\tb// tail\r\n  c",
        "/***/a", "/* /* */ */", "x\n /*", "x//\n/*abc*", "*/", "x /*/ ",
        "fn let mut own alloc if else while bound for in return requires ensures as true false "
        "u8 u16 u32 u64 i8 i16 i32 i64 bool struct arena pool handle import bytes cells",
        "free drop delete dealloc effect cap capability mint revoke grant publish promote authority admin "
        "syscall io print extern unsafe asm loop match enum var const self rec break continue",
        "_ _1 _fn fn0 xif Fn IF XAuthority capabilityX requires1 authorityy authoritx capability_",
        "( ) { } [ ] , ; : -> .. = + - * / % & | ^ ~ ! && || << >> == != < <= > >= .",
        "...->> &&& ||| !== <<==", "0 42 0xff 0b10 18446744073709551615",
        "00x", "0x", "0b2", "1_a", "18446744073709551616", "18446744073709551616z",
        "x \n  @", "x \n /* unfinished", "x\t// trivia before EOF"
    };
    for (size_t i = 0; i < sizeof inputs / sizeof *inputs; ++i) {
        size_t len = strlen(inputs[i]);
        for (uint32_t cap = 0; cap <= len + 1; ++cap)
            compare(inputs[i], inputs[i], len, cap);
    }
    compare("empty null span", NULL, 0, 1);
    for (unsigned i = 0; i <= 255; ++i) {
        char s[] = {'a', '\n', ' ', (char)i, 'z'};
        compare("all byte values", s, sizeof s, sizeof s + 1);
        s[0] = '/'; s[1] = '*'; s[3] = (char)i; s[4] = '*';
        compare("byte in unfinished comment", s, sizeof s, 0);
    }
    char name[OSC_LEX_NAME_MAX + 2];
    memset(name, 'a', sizeof name);
    for (size_t n = sizeof name - 3; n <= sizeof name; ++n)
        compare("identifier limit", name, n, 2);
    char wide[256];
    memset(wide, '0', sizeof wide);
    wide[sizeof wide - 1] = '1';
    compare("leading zeroes", wide, sizeof wide, 2);
    memset(wide, '9', sizeof wide);
    compare("long overflow", wide, sizeof wide, 2);
    wide[sizeof wide - 1] = '_';
    compare("long malformed", wide, sizeof wide, 2);

    char *dense = malloc(OSC_LEX_MAX_TOKENS);
    if (!dense) abort();
    memset(dense, ';', OSC_LEX_MAX_TOKENS);
    compare("last slot for EOF", dense, OSC_LEX_MAX_TOKENS - 1, OSC_LEX_MAX_TOKENS);
    compare("no slot for EOF", dense, OSC_LEX_MAX_TOKENS, OSC_LEX_MAX_TOKENS);
    free(dense);
    for (int i = 1; i < argc; ++i) file_case(argv[i]);
    printf("OSC_LEX_PARITY_PASS cases=%u files=%d\n", cases, argc - 1);
    return 0;
}
