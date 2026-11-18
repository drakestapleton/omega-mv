# mutgen.awk: single-line mutants of the functions named in FNS (space separated).
# Output rows: name TAB fn TAB occurrence TAB old line TAB new line (the mutants.tsv format).
BEGIN {
  n = split(FNS, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1
  split("lt:le lt:gt le:lt le:ge gt:ge gt:lt ge:gt ge:le eq:ne ne:eq slt:sle sle:slt add:sub sub:add mul:div div:mul umin:umax umax:umin sadd:sdif sdif:sadd and:or or:and true:false false:true shl:shr shr:shl", ops, " ")
  for (i in ops) { split(ops[i], p, ":"); rep[p[1]] = (p[1] in rep) ? rep[p[1]] " " p[2] : p[2] }
  T = "\t"
}
function emit(kind, nw) { cnt++; printf "g%04d-%s-%s%s%s%s%d%s%s%s%s\n", cnt, fn, kind, T, fn, T, occ[fn SUBSEP $0], T, $0, T, nw }
function joinw(k, r,   s, j) { s = ""; for (j = 1; j <= nw0; j++) s = s (j > 1 ? " " : "") (j == k ? r : w[j]); return s }
$1 == "fn" { fn = $2; infn = ($2 in want); next }
!infn { next }
$1 == "note" || $1 == "end" || $1 == "else" || $1 == "break" || $1 == "continue" { next }
{
  occ[fn SUBSEP $0]++
  nw0 = split($0, w, " ")
  for (k = 1; k <= nw0; k++) {
    if (w[k] in rep) { m = split(rep[w[k]], rr, " "); for (q = 1; q <= m; q++) emit("op", joinw(k, rr[q])) }
    else if (w[k] ~ /^[0-9]+$/ && w[k - 1] != "bound") {
      emit("c+", joinw(k, w[k] + 1))
      if (w[k] > 0) emit("c-", joinw(k, w[k] - 1))
    }
  }
  if (w[1] == "if") {
    emit("if", "if true"); emit("if", "if false")
    if (w[2] == "not") emit("if", "if " substr($0, 8)); else emit("if", "if not " substr($0, 4))
  } else if (w[1] == "while" || w[1] == "for" || w[1] == "ret") {
  } else emit("del", "note mutant")
}
