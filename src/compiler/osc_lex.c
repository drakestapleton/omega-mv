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
 * osc_lex.c -- OSC-1 lexer. See osc_lex.h.
 * OSC-1 slice; not a general Omega compiler; no self-hosting.
 */
#include "osc_lex.h"
#include "omega_api_decl.h"
#include "omega_native.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *const kind_names[OT__COUNT] = {
    "end of input", "NAME", "INT", "reserved word",
    "fn", "let", "mut", "own", "alloc", "if", "else", "while", "bound", "for", "in", "return", "requires",
    "ensures", "as", "true", "false", "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "bool",
    "(", ")", "{", "}", "[", "]", ",", ";", ":", "->", "..", "=",
    "+", "-", "*", "/", "%", "&", "|", "^", "~", "!", "&&", "||", "<<", ">>", "==", "!=", "<", "<=", ">", ">=",
    "struct", ".", "arena", "pool", "handle", "import",
    "bytes", "cells",
};

const char *osc_tok_kind_name(int kind)
{
    return (kind >= 0 && kind < OT__COUNT) ? kind_names[kind] : "?";
}

void osc_tok_text(const char *src, const OscToken *t, char *buf, size_t cap)
{
    size_t n = t->len;
    if (cap == 0) return;
    if (n >= cap) n = cap - 1;
    memcpy(buf, src + t->off, n);
    buf[n] = 0;
}

/* Omega selects the refusal and its source location. Keep formatting at the
 * OscDiag boundary so all compiler diagnostics use the same representation. */
static void lex_diag(OscDiag *d, uint64_t status, const char *src, const OscLexState *s,
                     const OscToken *t, uint32_t cap)
{
    char text[64];
    switch (status) {
    case OSC_LEX_COMMENT:
        osc_diag_set(d, OSC_DIAG_SYNTAX, s->line, s->col, "/*", 0, NULL, "unterminated comment",
                     "unterminated /* comment");
        break;
    case OSC_LEX_FULL:
        osc_diag_set(d, OSC_DIAG_CAPACITY, s->line, s->col, "unit", 0, NULL, "token capacity",
                     "more than %u tokens", cap);
        break;
    case OSC_LEX_NAME_LONG:
        osc_tok_text(src, t, text, sizeof text);
        osc_diag_set(d, OSC_DIAG_CAPACITY, s->line, s->col, text, 0, NULL, "identifier length",
                     "identifier longer than %d characters", OSC_LEX_NAME_MAX);
        break;
    case OSC_LITERAL_MALFORMED:
        osc_tok_text(src, t, text, sizeof text);
        osc_diag_set(d, OSC_DIAG_SYNTAX, s->line, s->col, text, 0, NULL, "malformed literal",
                     "malformed integer literal '%s'", text);
        break;
    case OSC_LITERAL_OVERFLOW:
        osc_tok_text(src, t, text, sizeof text);
        osc_diag_set(d, OSC_DIAG_OVERFLOW_UNSAFE, s->line, s->col, text, 0, NULL, "literal wider than 64 bits",
                     "integer literal does not fit in 64 bits");
        break;
    case OSC_LEX_BAD_BYTE: {
        unsigned char c = (unsigned char)src[s->start];
        if (c >= 0x20 && c < 0x7f) {
            text[0] = (char)c;
            text[1] = 0;
        } else {
            snprintf(text, sizeof text, "\\x%02x", (unsigned)c);
        }
        osc_diag_set(d, OSC_DIAG_SYNTAX, s->line, s->col, text, 0, NULL, "unexpected character",
                     "unexpected character '%s'", text);
        break;
    }
    default:
        abort();
    }
}

int osc_lex(const char *src, size_t len, OscToken *toks, uint32_t cap, uint32_t *ntok, OscDiag *d)
{
    OscLexState cursor = {.line = 1, .col = 1};
    _Static_assert(sizeof(OscToken) == 32 && offsetof(OscToken, kind) == 0 && offsetof(OscToken, line) == 4 &&
                   offsetof(OscToken, col) == 8 && offsetof(OscToken, off) == 12 && offsetof(OscToken, len) == 16 &&
                   offsetof(OscToken, ival) == 24, "OSC token layout must match osc_lex_stream");
    _Static_assert(OSC_LEX_NAME_MAX == 63, "OSC scanner identifier width");
    uint64_t count = 0;
    if (len > UINT32_MAX) {
        osc_diag_set(d, OSC_DIAG_CAPACITY, 1, 1, "unit", 0, NULL, "source offset capacity",
                     "source exceeds the OSC 32-bit offset range");
        return -1;
    }
    uint64_t status;
    uint32_t bridge = omega2_osc_lex_stream(&status, (const uint8_t *)src, len, (uint8_t *)&cursor,
                                            (uint8_t *)toks, (size_t)cap * sizeof *toks, &count, 1);
    if (bridge != OMEGA_OK) {
        osc_diag_set(d, OSC_DIAG_CAPACITY, cursor.line, cursor.col, "unit", 0, NULL, "scanner capacity",
                     "scanner could not represent or allocate its input state");
        return -1;
    }
    if (status) {
        const OscToken *t = status == OSC_LEX_FULL || status == OSC_LEX_COMMENT ? NULL : &toks[count];
        lex_diag(d, status, src, &cursor, t, cap);
        return -1;
    }
    *ntok = (uint32_t)count;
    return 0;
}
