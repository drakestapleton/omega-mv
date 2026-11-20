/* SPDX-License-Identifier: Apache-2.0 */
/* Both parsers receive the same tokens, source and initial AST contents. */
#include "osc_parse.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int osc_parse_reference(OscAst *, OscDiag *);

static OscAst old_ast, new_ast;
static OscToken tokens[OSC_LEX_MAX_TOKENS];
static unsigned passed, lex_refusals;

static void compare(const char *label, const char *src, size_t size)
{
    OscDiag old_diag = {0}, new_diag = {0};
    uint32_t count;
    if (osc_lex(src, size, tokens, OSC_LEX_MAX_TOKENS, &count, &new_diag)) {
        ++lex_refusals;
        return;
    }
    memset(&old_ast, 0, sizeof old_ast);
    old_ast.src = src;
    old_ast.toks = tokens;
    old_ast.ntok = count;
    memcpy(&new_ast, &old_ast, sizeof old_ast);
    int want = osc_parse_reference(&old_ast, &old_diag);
    int got = osc_parse(&new_ast, &new_diag);
    if (want != got || memcmp(&old_diag, &new_diag, sizeof old_diag) ||
        memcmp(&old_ast, &new_ast, sizeof old_ast)) {
        fprintf(stderr, "FAIL %s\nC (%d) %u:%u %s\nOmega (%d) %u:%u %s\n",
                label, want, old_diag.line, old_diag.col, old_diag.message,
                got, new_diag.line, new_diag.col, new_diag.message);
        exit(1);
    }
    ++passed;
}

static void file_case(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f || fseek(f, 0, SEEK_END)) { perror(path); exit(1); }
    long size = ftell(f);
    if (size < 0 || fseek(f, 0, SEEK_SET)) { perror(path); exit(1); }
    char *src = malloc((size_t)size + 1);
    if (!src || fread(src, 1, (size_t)size, f) != (size_t)size) abort();
    fclose(f);
    compare(path, src, (size_t)size);
    free(src);
}

static void expression_cases(void)
{
    static const char *const operators[] = {
        "||", "&&", "==", "!=", "<", "<=", ">", ">=", "|", "^", "&",
        "<<", ">>", "+", "-", "*", "/", "%"
    };
    static const char *const forms[] = {
        "a %s b %s c", "(a %s b) %s c", "a %s (b %s c)", "a %s -b %s"
    };
    char src[256];
    for (size_t i = 0; i < sizeof operators / sizeof *operators; ++i) {
        for (size_t j = 0; j < sizeof operators / sizeof *operators; ++j) {
            for (size_t k = 0; k < sizeof forms / sizeof *forms; ++k) {
                char expr[64];
                int ne = snprintf(expr, sizeof expr, forms[k], operators[i], operators[j]);
                int n = snprintf(src, sizeof src, "fn f() -> u64 { return %s; }", expr);
                if (ne < 0 || (size_t)ne >= sizeof expr || n < 0 || (size_t)n >= sizeof src) abort();
                compare(src, src, (size_t)n);
            }
        }
    }
    static const char *const edge[] = {
        "fn f() -> u64 { return a || b && c == d | e ^ f & g << h + i * j; }",
        "fn f() -> u64 { return a * b + c << d & e ^ f | g == h && i || j; }",
        "fn f() -> u64 { return a == b * c < d; }",
        "fn f() -> u64 { return a == b && c == d; }",
        "fn f() -> i32 { return !~-f(1, x[0]) as i32; }",
        "fn f() -> i32 { return (x as i8) as i32; }",
        "fn f() -> i32 { return -x as i8 as i32; }",
        "fn f() -> i32 { return ~-!x as", "fn f() -> i32 { return ~-!; }",
        "fn f() -> i32 { return !p.alloc(f(x.field[0])); }",
        "fn f() -> u64 { return a * (b + c", "fn f() -> u64 { return -(-a) << ~b; }"
    };
    for (size_t i = 0; i < sizeof edge / sizeof *edge; ++i)
        compare(edge[i], edge[i], strlen(edge[i]));
}

int main(int argc, char **argv)
{
    static const char *const contexts[] = {
        "struct S { v:u8 } fn f(x:\n %s) {}",
        "struct S { v:u8 } fn f() ->\n %s {}",
        "struct S { v:u8 } struct T { member:\n %s }",
        "struct S { v:u8 } fn f() { let x:\n %s = 1; }",
        "fn f() -> u8 { return 1 as\n %s; }"
    };
    static const char *const types[] = {
        "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "bool", "bytes",
        "cells", "S", "Missing", "pool", "handle", "unsafe", "mut", "", "[",
        "[bool", "[u8 1]", "[u8;", "[u8;n]", "[u8;0]", "[u8;1]", "[u8;64]",
        "[u8;65]", "[u8;18446744073709551615]", "[bytes;1]", "[cells;1]",
        "[free;1]", "[u8;1 free", "own", "own S", "own Missing", "own [u8;3]",
        "&", "& S", "& Missing", "&mut", "&mut S", "&mut Missing",
        "&mut [", "&mut [i64", "&mut [i64;", "&mut [i64;2", "&mut [i64;2]",
        "&mut [u8;0]", "&mut [u8;65]", "&mut [i64;2 free", "& mut pool"
    };
    for (int i = 1; i < argc; ++i) file_case(argv[i]);
    unsigned before = lex_refusals;
    char src[256];
    for (size_t i = 0; i < sizeof types / sizeof *types; ++i) {
        for (size_t j = 0; j < sizeof contexts / sizeof *contexts; ++j) {
            int n = snprintf(src, sizeof src, contexts[j], types[i]);
            if (n < 0 || (size_t)n >= sizeof src) abort();
            compare(src, src, (size_t)n);
        }
        int n = snprintf(src, sizeof src, "fn f(x:\n %s", types[i]);
        if (n < 0 || (size_t)n >= sizeof src) abort();
        compare(src, src, (size_t)n);
    }
    expression_cases();
    if (lex_refusals != before) abort(); /* All constructed cases must reach the parser. */
    printf("OSC_PARSE_PARITY_PASS parsed=%u lexer_refusals=%u files=%d\n", passed, lex_refusals, argc - 1);
    return 0;
}
