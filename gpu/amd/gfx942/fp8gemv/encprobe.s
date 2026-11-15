// encprobe, gfx942. Same words as encprobe.isa.
.text
global_load_dwordx4 v[0:3], v[0:1], off
global_load_dwordx4 v[0:3], v[0:1], off sc0
global_load_dwordx4 v[0:3], v[0:1], off sc1
global_load_dwordx4 v[0:3], v[0:1], off nt
global_load_dwordx4 v[0:3], v[0:1], off sc0 sc1
global_load_dwordx4 v[0:3], v[0:1], off sc0 nt
global_load_dwordx4 v[0:3], v[0:1], off nt sc1
global_load_dwordx4 v[0:3], v[0:1], off sc0 nt sc1
global_load_dwordx4 v[0:3], v0, s[0:1]
global_load_dwordx4 v[0:3], v0, s[0:1] nt
global_load_dwordx4 v[4:7], v1, s[2:3] offset:16
global_load_dwordx4 v[4:7], v1, s[2:3] offset:16 nt
buffer_load_dwordx4 v[0:3], v0, s[0:3], 0 offen
buffer_load_dwordx4 v[0:3], v0, s[0:3], 0 offen sc0
buffer_load_dwordx4 v[0:3], v0, s[0:3], 0 offen sc1
buffer_load_dwordx4 v[0:3], v0, s[0:3], 0 offen nt
buffer_load_dwordx4 v[0:3], v0, s[0:3], 0 offen sc0 sc1
buffer_load_dwordx4 v[0:3], v0, s[0:3], 0 offen sc0 nt
buffer_load_dwordx4 v[0:3], v0, s[0:3], 0 offen nt sc1
buffer_load_dwordx4 v[0:3], v0, s[0:3], 0 offen sc0 nt sc1
buffer_wbl2
buffer_inv
buffer_wbl2 sc0
buffer_inv sc0
buffer_wbl2 sc1
buffer_inv sc1
buffer_wbl2 sc0 sc1
buffer_inv sc0 sc1
global_atomic_add v0, v[0:1], v2, off sc0
global_atomic_add v0, v[0:1], v2, off sc0 sc1
global_atomic_add v0, v[0:1], v2, off sc0 nt
global_atomic_add v0, v[0:1], v2, off sc0 nt sc1
global_atomic_add v4, v2, s[6:7]
global_atomic_add v4, v2, s[6:7] sc1
global_atomic_add v4, v2, s[6:7] nt
global_atomic_add v4, v2, s[6:7] nt sc1
s_endpgm
