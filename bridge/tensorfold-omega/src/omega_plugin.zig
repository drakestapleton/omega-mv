// SPDX-License-Identifier: Apache-2.0
// bridge/tensorfold-omega/src/omega_plugin.zig
//
// Zero-touch Zig ABI v2 drop-in plugin for TensorFold (`--backend omega`).
// Links statically or dynamically against the `bridge/omega-bridge/src/native.om`
// generated ABI v2 library (`libtf_omega_native.a`), preserving 100% byte-level
// cryptographic traceability via `omega2_ident_tf_omega_unit()` and `TF_OMEGA.lock`.

const std = @import("std");

pub const OMEGA_OK: u32 = 0;
pub const OMEGA_BAD_ARG: u32 = 32;
pub const OMEGA_REENTRY: u32 = 33;
pub const OMEGA_BAD_RT: u32 = 34;
pub const OMEGA_NO_STACK: u32 = 35;

pub const TF_OMEGA_MAGIC: u64 = 0x4f4d544630303032; // "OMTF0002"
pub const TF_MIN_RAW_FLOOR: u64 = 6;
pub const TF_PRED_CAP: usize = 16;
pub const TF_NONE: u32 = 0xffffffff;

pub const FLAG_ANCHOR: u64 = 1 << 0;
pub const FLAG_FIXED_ALU: u64 = 1 << 1;

// Raw ABI v2 declarations matching `bridge/omega-bridge/src/native.om zig` byte-for-byte.
pub extern "c" fn omega2_tf_arboris_observe(
    result: ?*u64,
    o_table: ?[*]u32,
    o_table_len: u64,
    o_cfg: ?[*]const u64,
    o_cfg_len: u64,
    o_prev_eid: u64,
    o_cur_ids: ?[*]const u32,
    o_cur_ids_len: u64,
) u32;

pub extern "c" fn omega2_tf_arboris_predict(
    result: ?*u64,
    o_table: ?[*]const u32,
    o_table_len: u64,
    o_cfg: ?[*]const u64,
    o_cfg_len: u64,
    o_cur_ids: ?[*]const u32,
    o_cur_ids_len: u64,
    o_pred: ?[*]u32,
) u32;

pub extern "c" fn omega2_tf_sm121_check_stall(
    result: ?*u64,
    o_insns: ?[*]const u64,
    o_insns_len: u64,
    o_n_insns: u64,
    o_raw_floor: u64,
) u32;

pub extern "c" fn omega2_tf_egp3_check_cert(
    result: ?*u64,
    o_cert: ?[*]const u8,
    o_cert_len: u64,
) u32;

pub extern "c" fn omega2_tf_omega_ident(
    result: ?*u64,
    o_meta: ?[*]u64,
) u32;

pub extern "c" fn omega2_ident_tf_omega_unit() [*:0]const u8;

pub const OmegaError = error{
    Overflow,
    DivByZero,
    Bounds,
    LoopBound,
    Cast,
    Oom,
    Shift,
    Runtime,
    Requires,
    Ensures,
    ArenaFull,
    Stale,
    PoolFull,
    Retired,
    InvalidOrAlias,
    Reentry,
    BadRuntime,
    NoStack,
    IdentMismatch,
    UnknownTrap,
};

pub fn mapStatus(status: u32) OmegaError!void {
    return switch (status) {
        0 => {},
        1 => OmegaError.Overflow,
        2 => OmegaError.DivByZero,
        3 => OmegaError.Bounds,
        4 => OmegaError.LoopBound,
        5 => OmegaError.Cast,
        6 => OmegaError.Oom,
        7 => OmegaError.Shift,
        8 => OmegaError.Runtime,
        9 => OmegaError.Requires,
        10 => OmegaError.Ensures,
        11 => OmegaError.ArenaFull,
        12 => OmegaError.Stale,
        13 => OmegaError.PoolFull,
        14 => OmegaError.Retired,
        32 => OmegaError.InvalidOrAlias,
        33 => OmegaError.Reentry,
        34 => OmegaError.BadRuntime,
        35 => OmegaError.NoStack,
        else => OmegaError.UnknownTrap,
    };
}

/// Returns the static byte-traceable `omega-ident 1 unit=tf_omega_unit ...` string embedded
/// in the compiled ABI v2 object.
pub fn identString() []const u8 {
    return std.mem.span(omega2_ident_tf_omega_unit());
}

/// Verifies the linked ABI v2 object identity matches an expected lockfile `OMEGA2_IDENT`.
pub fn verifyIdent(expected: []const u8) OmegaError!void {
    if (!std.mem.eql(u8, identString(), expected)) {
        return OmegaError.IdentMismatch;
    }
}

pub const PluginMeta = struct {
    magic: u64,
    abi_version: u64,
    profile: u64,
    capabilities: u64,
    min_raw_floor: u64,
    export_count: u64,
};

/// Queries ABI v2 runtime capability and floor metadata via `omega2_tf_omega_ident`.
pub fn pluginMetadata() OmegaError!PluginMeta {
    var raw: u64 = 0;
    var meta: [6]u64 = .{ 0, 0, 0, 0, 0, 0 };
    try mapStatus(omega2_tf_omega_ident(&raw, &meta));
    return .{
        .magic = meta[0],
        .abi_version = meta[1],
        .profile = meta[2],
        .capabilities = meta[3],
        .min_raw_floor = meta[4],
        .export_count = meta[5],
    };
}

/// Zero-drift Live Arboris MoE co-activation prefetcher.
/// Operates strictly on caller-owned `table` storage and never touches logits or output tokens.
pub const ArborisPrefetcher = struct {
    table: []u32,
    cfg: [4]u64,

    pub fn init(table: []u32, n_exp: u64, n_slots: u64, top_k_pred: u64, decay_at: u64) ArborisPrefetcher {
        @memset(table, 0);
        return .{
            .table = table,
            .cfg = .{ n_exp, n_slots, top_k_pred, decay_at },
        };
    }

    pub fn observe(self: *ArborisPrefetcher, prev_eid: u64, cur_ids: []const u32) OmegaError!u64 {
        var updated: u64 = 0;
        try mapStatus(omega2_tf_arboris_observe(
            &updated,
            self.table.ptr,
            self.table.len,
            &self.cfg,
            self.cfg.len,
            prev_eid,
            cur_ids.ptr,
            cur_ids.len,
        ));
        return updated;
    }

    pub const Prediction = struct {
        ids: [TF_PRED_CAP]u32,
        count: usize,

        pub fn slice(self: *const Prediction) []const u32 {
            return self.ids[0..self.count];
        }
    };

    pub fn predict(self: *const ArborisPrefetcher, cur_ids: []const u32) OmegaError!Prediction {
        var count: u64 = 0;
        var out_ids: [TF_PRED_CAP]u32 = undefined;
        @memset(&out_ids, TF_NONE);
        try mapStatus(omega2_tf_arboris_predict(
            &count,
            self.table.ptr,
            self.table.len,
            &self.cfg,
            self.cfg.len,
            cur_ids.ptr,
            cur_ids.len,
            &out_ids,
        ));
        return .{
            .ids = out_ids,
            .count = @intCast(count),
        };
    }
};

/// Packed 4-word SM121 instruction schedule descriptor matching `tf_sm121_check_stall`.
pub const Sm121Insn = struct {
    stall: u64,
    dst_reg: u64,
    src0: u8 = 255,
    src1: u8 = 255,
    src2: u8 = 255,
    anchor: bool = false,
    fixed_alu: bool = false,
    bb_id: u16 = 0,
    orig_bb_id: u16 = 0,

    pub fn pack(self: Sm121Insn) [4]u64 {
        const srcs: u64 = @as(u64, self.src0) | (@as(u64, self.src1) << 8) | (@as(u64, self.src2) << 16);
        var flags: u64 = (@as(u64, self.bb_id) << 8) | (@as(u64, self.orig_bb_id) << 24);
        if (self.anchor) flags |= FLAG_ANCHOR;
        if (self.fixed_alu) flags |= FLAG_FIXED_ALU;
        return .{ self.stall, self.dst_reg, srcs, flags };
    }
};

pub const Sm121Verdict = enum(u64) {
    pass = 0,
    raw_stall_underflow = 1,
    bb_pin_escape = 2,
    bb_non_monotonic = 3,
    fixed_alu_floor_underflow = 4,
    _,
};

/// Verifies SM121 scoreboard RAW stall-floor (`raw_floor >= 6` enforced via OM-2 `requires`)
/// and basic-block pinning across `words` (`4 * n_insns` packed `u64` words).
pub fn checkSm121StallWords(words: []const u64, n_insns: u64, raw_floor: u64) OmegaError!Sm121Verdict {
    var rc: u64 = 0;
    try mapStatus(omega2_tf_sm121_check_stall(
        &rc,
        words.ptr,
        words.len,
        n_insns,
        raw_floor,
    ));
    return @enumFromInt(rc);
}

/// Verifies a binary `EGP3` single-cert structural rewrite proof.
/// Returns `0` on PASS or nonzero refusal code `1..10`.
pub fn checkEgp3Cert(cert: []const u8) OmegaError!u64 {
    var rc: u64 = 0;
    try mapStatus(omega2_tf_egp3_check_cert(&rc, cert.ptr, cert.len));
    return rc;
}

/// Defensive ABI v2 probe: null buffer with nonzero length -> status 32 (`OMEGA_BAD_ARG`).
pub fn probeNullArg() u32 {
    var out: u64 = 0;
    return omega2_tf_egp3_check_cert(&out, null, 36);
}

/// Defensive ABI v2 probe: aliased `result` and `out` buffer -> status 32 (`OMEGA_BAD_ARG`).
pub fn probeAliasedOut() u32 {
    var meta: [6]u64 = .{ 0, 0, 0, 0, 0, 0 };
    return omega2_tf_omega_ident(&meta[0], &meta);
}

// ---- Embedded Zig ABI v2 verification tests ----

test "omega2 ident and capability metadata" {
    const id = identString();
    try std.testing.expect(std.mem.startsWith(u8, id, "omega-ident 1 unit=tf_omega_unit abi=2 profile=OM-2 src="));
    try std.testing.expect(std.mem.indexOf(u8, id, " omc=") != null);
    try verifyIdent(id);
    try std.testing.expectError(OmegaError.IdentMismatch, verifyIdent("omega-ident tampered"));

    const meta = try pluginMetadata();
    try std.testing.expectEqual(TF_OMEGA_MAGIC, meta.magic);
    try std.testing.expectEqual(@as(u64, 2), meta.abi_version);
    try std.testing.expectEqual(@as(u64, 2), meta.profile);
    try std.testing.expectEqual(@as(u64, 7), meta.capabilities);
    try std.testing.expectEqual(TF_MIN_RAW_FLOOR, meta.min_raw_floor);
    try std.testing.expectEqual(@as(u64, 5), meta.export_count);
}

test "zero-drift Live Arboris MoE observe and predict" {
    var table: [128 * 8]u32 = undefined;
    var pf = ArborisPrefetcher.init(&table, 128, 8, 4, 60000);

    // Observe strong co-activation from expert 3 -> experts 17, 42 (repeated) and 99 (once).
    const obs_a = [_]u32{ 17, 42 };
    const obs_b = [_]u32{ 17, 99 };
    try std.testing.expectEqual(@as(u64, 2), try pf.observe(3, &obs_a));
    try std.testing.expectEqual(@as(u64, 2), try pf.observe(3, &obs_a));
    try std.testing.expectEqual(@as(u64, 2), try pf.observe(3, &obs_b));

    // Pure read-only prediction ranks expert 17 (count 3) first, 42 (count 2) second, 99 (count 1) third.
    const cur = [_]u32{3};
    const pred = try pf.predict(&cur);
    try std.testing.expectEqual(@as(usize, 3), pred.count);
    try std.testing.expectEqual(@as(u32, 17), pred.slice()[0]);
    try std.testing.expectEqual(@as(u32, 42), pred.slice()[1]);
    try std.testing.expectEqual(@as(u32, 99), pred.slice()[2]);
}

test "SM121 scoreboard stall-floor >= 6 and basic-block pinning" {
    // Valid 2-instruction schedule in BB 0: producer R4 with stall=6, consumer reads R4.
    const ok_insns = [_][4]u64{
        (Sm121Insn{ .stall = 6, .dst_reg = 4, .fixed_alu = true, .bb_id = 0, .orig_bb_id = 0 }).pack(),
        (Sm121Insn{ .stall = 2, .dst_reg = 5, .src0 = 4, .bb_id = 0, .orig_bb_id = 0 }).pack(),
    };
    const ok_words: []const u64 = @as([*]const u64, @ptrCast(&ok_insns[0]))[0..8];
    try std.testing.expectEqual(Sm121Verdict.pass, try checkSm121StallWords(ok_words, 2, 6));

    // Negative control 1: raw_floor < 6 MUST trap 9 (OmegaError.Requires).
    try std.testing.expectError(OmegaError.Requires, checkSm121StallWords(ok_words, 2, 5));
    try std.testing.expectError(OmegaError.Requires, checkSm121StallWords(ok_words, 2, 0));

    // Negative control 2: RAW stall span < 6 MUST be refused (raw_stall_underflow = 1).
    const bad_stall = [_][4]u64{
        (Sm121Insn{ .stall = 4, .dst_reg = 4, .bb_id = 0, .orig_bb_id = 0 }).pack(),
        (Sm121Insn{ .stall = 2, .dst_reg = 5, .src0 = 4, .bb_id = 0, .orig_bb_id = 0 }).pack(),
    };
    const bad_stall_words: []const u64 = @as([*]const u64, @ptrCast(&bad_stall[0]))[0..8];
    try std.testing.expectEqual(Sm121Verdict.raw_stall_underflow, try checkSm121StallWords(bad_stall_words, 2, 6));

    // Negative control 3: instruction moved across basic-block boundary MUST be refused (bb_pin_escape = 2).
    const bad_bb = [_][4]u64{
        (Sm121Insn{ .stall = 6, .dst_reg = 4, .bb_id = 1, .orig_bb_id = 0 }).pack(),
        (Sm121Insn{ .stall = 6, .dst_reg = 5, .src0 = 4, .bb_id = 1, .orig_bb_id = 1 }).pack(),
    };
    const bad_bb_words: []const u64 = @as([*]const u64, @ptrCast(&bad_bb[0]))[0..8];
    try std.testing.expectEqual(Sm121Verdict.bb_pin_escape, try checkSm121StallWords(bad_bb_words, 2, 6));
}

test "EGP3 structural checker positive and negative controls" {
    // Build a minimal valid 240-byte EGP3 Rule-1 cert: add(mul(a,b), c) = fma(a,b,c).
    var cert: [240]u8 = undefined;
    @memset(&cert, 0);
    @memcpy(cert[0..4], "EGP3");
    std.mem.writeInt(u32, cert[4..8], 1, .little); // cert_count
    std.mem.writeInt(u32, cert[16..20], 64, .little); // width_bits
    std.mem.writeInt(u32, cert[20..24], 6, .little); // node_count
    std.mem.writeInt(u32, cert[24..28], 4, .little); // root_before
    std.mem.writeInt(u32, cert[28..32], 5, .little); // root_after
    std.mem.writeInt(u32, cert[32..36], 1, .little); // trace_count

    const nodes = [_][8]u32{
        .{ 2, 0, 0, 0, 0, 0, 64, 0 }, // 0: a
        .{ 2, 0, 0, 0, 1, 0, 64, 0 }, // 1: b
        .{ 2, 0, 0, 0, 2, 0, 64, 0 }, // 2: c
        .{ 5, 0, 1, 0, 0, 0, 64, 0 }, // 3: mul(a, b)
        .{ 3, 3, 2, 0, 0, 0, 64, 0 }, // 4: add(mul(a, b), c)
        .{ 6, 0, 1, 2, 0, 0, 64, 0 }, // 5: fma(a, b, c)
    };
    for (nodes, 0..) |nd, i| {
        for (nd, 0..) |w, f| {
            const off = 36 + i * 32 + f * 4;
            std.mem.writeInt(u32, cert[off..][0..4], w, .little);
        }
    }
    std.mem.writeInt(u32, cert[228..232], 1, .little); // rule 1
    std.mem.writeInt(u32, cert[232..236], 4, .little); // lhs
    std.mem.writeInt(u32, cert[236..240], 5, .little); // rhs

    try std.testing.expectEqual(@as(u64, 0), try checkEgp3Cert(&cert));

    // Tamper Rule 1 RHS operand (swap c -> 0): MUST be refused with nonzero code 8.
    cert[36 + 5 * 32 + 3 * 4] = 0;
    try std.testing.expectEqual(@as(u64, 8), try checkEgp3Cert(&cert));
}

test "ABI v2 null and alias probes return status 32" {
    try std.testing.expectEqual(OMEGA_BAD_ARG, probeNullArg());
    try std.testing.expectEqual(OMEGA_BAD_ARG, probeAliasedOut());
}
