# SPDX-License-Identifier: Apache-2.0
# cfuncs.awk -- prints the name of every function a C file DEFINES with external linkage (not
# `static`), one per line, in source order. Used by tools/migration/parity_check.sh.
# Comments and string/character literals are removed and preprocessor lines dropped; then, at
# brace depth 0, the text before each `{` is a function definition when it ends in `)` and holds
# a `(` (no `static`, `typedef` or `=`); the name is the identifier before the first `(`. A line
# that invokes a function-defining macro of the same file (a #define whose body holds `{`), as
# `VERIFY_FN(tyqr_profile_verify, ...)`, defines the function named by its first argument.
function flush_decl(d,   name, p) {
    gsub(/[ \t\n]+/, " ", d)
    sub(/^ /, "", d); sub(/ $/, "", d)
    if (d !~ /\)$/) return
    if (d !~ /\(/) return
    if (d ~ /(^|[^A-Za-z0-9_])(static|typedef)([^A-Za-z0-9_]|$)/) return
    if (d ~ /=/) return
    p = index(d, "(")
    name = substr(d, 1, p - 1)
    sub(/ +$/, "", name)
    if (!match(name, /[A-Za-z_][A-Za-z0-9_]*$/)) return
    name = substr(name, RSTART, RLENGTH)
    if (name ~ /^(if|while|for|switch|return|sizeof)$/) return
    print name
}
BEGIN { RS = "\001" }
{
    s = $0
    out = ""; n = length(s); i = 1
    while (i <= n) {
        c = substr(s, i, 1); c2 = substr(s, i, 2)
        if (c2 == "/*") { j = index(substr(s, i + 2), "*/"); if (j == 0) break; i += j + 3; out = out " "; continue }
        if (c2 == "//") { j = index(substr(s, i), "\n"); if (j == 0) break; i += j - 1; continue }
        if (c == "\"" || c == "'") {
            q = c; i++
            while (i <= n) { d = substr(s, i, 1); if (d == "\\") { i += 2; continue } if (d == q) break; i++ }
            i++; out = out q q; continue
        }
        out = out c; i++
    }
    m = split(out, L, "\n"); t = ""; cont = 0; inm = ""
    for (k = 1; k <= m; k++) {
        if (cont || L[k] ~ /^[ \t]*#/) {
            if (!cont && match(L[k], /^[ \t]*#[ \t]*define[ \t]+[A-Za-z_][A-Za-z0-9_]*\(/)) {
                inm = L[k]; sub(/^[ \t]*#[ \t]*define[ \t]+/, "", inm); sub(/\(.*/, "", inm)
            } else if (!cont) inm = ""
            if (inm != "" && L[k] ~ /\{/) FM[inm] = 1
            cont = (L[k] ~ /\\[ \t]*$/)
            if (!cont) inm = ""
            t = t "\n"
            continue
        }
        if (match(L[k], /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\([ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
            mac = L[k]; sub(/^[ \t]*/, "", mac); sub(/[ \t]*\(.*/, "", mac)
            if (mac in FM) {
                a = L[k]; sub(/^[^(]*\([ \t]*/, "", a); sub(/[^A-Za-z0-9_].*/, "", a)
                MACDEF[k] = a
            }
        }
        t = t L[k] "\n"
    }
    # emit in source order: macro definitions are interleaved by line number
    depth = 0; decl = ""; n = length(t); line = 1
    for (i = 1; i <= n; i++) {
        c = substr(t, i, 1)
        if (c == "\n") { if (line in MACDEF && depth == 0) { print MACDEF[line]; decl = "" } line++ }
        if (c == "{") { if (depth == 0) flush_decl(decl); depth++; decl = ""; continue }
        if (c == "}") { depth--; if (depth == 0) decl = ""; continue }
        if (depth == 0) { if (c == ";") decl = ""; else decl = decl c }
    }
}
