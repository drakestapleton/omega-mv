Functional negative control for `hand check` (review finding 4 on f4d82f3a: the hand-off's control
files lived in /tmp and were never committed; bay 10 rebuilt them, these are byte-identical).

noeor.spec / noeor.words = bcopy-B with its `eor x9, x8, x1` removed and the following store changed
from `strb w9` to `strb w8` (word 38246969 -> 38246968). The loop branch keeps bcopy-B's offset.

Expected (gate): `hand splice noeor.spec noeor.words <omc bcopy> OUT` rc 0, `hand check noeor.spec`
on OUT's objdump rc 0 (spec and words agree), and OUT's stdout sha256 DIFFERS from
kernels/want/bcopy.sha256. The text check proves the words say what the spec says; only the output
referee proves the edit is semantically right, so every arm must pass both.

sha256: noeor.spec 3706e329c8effedb3af2..., noeor.words 25680ee073d360552c4e... (full values in the
gate log). Kept in a subdirectory so the gate's `hand/*.spec` arm loop never picks it up.
