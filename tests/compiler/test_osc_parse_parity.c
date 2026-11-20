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

/* Truncate after each token to compare diagnostic locations and partial AST
 * writes as well as the successful production. All variants reach the parser. */
static void statement_cases(void)
{
    static const char *const programs[] = {
        "fn f ( ) { return ; }", "fn f ( ) { return & mut x ; }",
        "fn f ( ) { x = & mut value ; }", "fn f ( ) { x = value + 1 ; }",
        "fn f ( ) { a [ i ] = value ; }", "fn f ( ) { a [ i ] = & value ; }",
        "fn f ( ) { x . member [ i ] = y ; }", "fn f ( ) { p . free ( f ( x ) ) ; }",
        "fn f ( ) { p . unsafe ( x ) ; }", "fn f ( ) { f ( x , y ) ; }",
        "fn f ( ) { while x bound 1 { } }", "fn f ( ) { while x bound 1000001 { } }",
        "fn f ( ) { arena a bound 64 { } }", "fn f ( ) { arena a bound 65 { } }",
        "fn f ( ) { for i in - 5 .. - 2 { } }", "fn f ( ) { for i in 3 .. 2 { } }",
        "fn f ( ) { for i in - 1 .. 999999 { } }", "fn f ( ) { for i in - 1 .. 1000000 { } }",
        "fn f ( ) { for i in - 9223372036854775808 .. - 9223372036854775807 { } }",
        "fn f ( ) { for i in - 9223372036854775809 .. 0 { } }",
        "fn f ( ) { for i in 9223372036854775807 .. 9223372036854775807 { } }",
        "fn f ( ) { for i in 0 .. 9223372036854775808 { } }",
        "import a ; import ab ; import abc ;", "import abc ; import ab ; import abc ;",
        "import x ; fn f ( ) { } import", "struct S { x : u8 } import unsafe ;",
        "fn f ( x : u8 ) requires ( x + 1 ) > 0 ensures ( x ) { return ; }"
    };
    for (size_t i = 0; i < sizeof programs / sizeof *programs; ++i) {
        const char *src = programs[i];
        for (size_t j = 0; src[j]; ++j)
            if (src[j] == ' ') compare(src, src, j);
        compare(src, src, strlen(src));
    }

    char imports[2048];
    size_t used = 0;
    for (unsigned i = 0; i < OSC_MAX_IMPORTS; ++i) {
        int n = snprintf(imports + used, sizeof imports - used, "import p%u;\n", i);
        if (n < 0 || (size_t)n >= sizeof imports - used) abort();
        used += (size_t)n;
    }
    compare("full import table", imports, used);
    static const char *const tails[] = {"import p0;", "import extra;", "import ;"};
    for (size_t i = 0; i < sizeof tails / sizeof *tails; ++i) {
        strcpy(imports + used, tails[i]);
        compare("import capacity diagnostic", imports, used + strlen(tails[i]));
    }

    /* Canonical text is four names separated by three " + " sequences.
     * Exercise capacity-1, capacity, and the first refused append. */
    for (size_t length = OSC_CLAUSE_MAX - 2; length <= OSC_CLAUSE_MAX + 1; ++length) {
        char src[512], names[4][OSC_LEX_NAME_MAX + 1];
        size_t remaining = length - 9;
        for (int i = 0; i < 4; ++i) {
            size_t width = remaining / (size_t)(4 - i);
            if (width > OSC_LEX_NAME_MAX) abort();
            memset(names[i], 'a' + i, width);
            names[i][width] = 0;
            remaining -= width;
        }
        int n = snprintf(src, sizeof src, "fn f() requires %s+%s+%s+%s {}",
                         names[0], names[1], names[2], names[3]);
        if (n < 0 || (size_t)n >= sizeof src) abort();
        compare("contract text capacity", src, (size_t)n);
    }
}

/* The C oracle subtracts int64_t ends before testing the trip count. A full
 * span overflows that subtraction, so check this case directly against the
 * specified diagnostic, including the location of the first range token. */
static void wide_for_range(void)
{
    const char *src = "fn f() { for i in\n-9223372036854775808 .. 9223372036854775807 {} }";
    OscDiag d = {0};
    uint32_t count;
    if (osc_lex(src, strlen(src), tokens, OSC_LEX_MAX_TOKENS, &count, &d)) abort();
    memset(&new_ast, 0, sizeof new_ast);
    new_ast.src = src;
    new_ast.toks = tokens;
    new_ast.ntok = count;
    if (osc_parse(&new_ast, &d) != -1 || d.kind != OSC_DIAG_UNBOUNDED_LOOP ||
        d.line != 2 || d.col != 1 ||
        strcmp(d.message, "for range must satisfy A <= B and B - A <= 1000000")) {
        fprintf(stderr, "FAIL full-width range: %u:%u %s\n", d.line, d.col, d.message);
        exit(1);
    }
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
    statement_cases();
    wide_for_range();
    if (lex_refusals != before) abort(); /* All constructed cases must reach the parser. */
    printf("OSC_PARSE_PARITY_PASS parsed=%u lexer_refusals=%u files=%d\n", passed, lex_refusals, argc - 1);
    return 0;
}
