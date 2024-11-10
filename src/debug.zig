const std = @import("std");
const Cpu = @import("Cpu.zig");

// ----- Blargg test rom output -----

var dbg_msg_buffer: [1024]u8 = @splat(0);
var dbg_msg_len: usize = 0;

pub fn update(cpu: *Cpu) void {
    if (cpu.bus.peek(0xFF02) == 0x81) {
        const char = cpu.bus.peek(0xFF01);
        dbg_msg_buffer[dbg_msg_len] = char;
        dbg_msg_len += 1;
        cpu.bus.set(0xFF02, 0);
    }
}

pub fn print() void {
    const Static = struct {
        var global_writer: std.io.BufferedWriter(4096, std.fs.File.Writer) = undefined;
        var init = false;
    };

    if (!Static.init) {
        const stdout = std.io.getStdOut();
        Static.global_writer = std.io.bufferedWriter(stdout.writer());
        Static.init = true;
    }

    const msg = dbg_msg_buffer[0..dbg_msg_len];
    if (std.mem.indexOf(u8, msg, "Failed") != null or std.mem.indexOf(u8, msg, "Passed") != null) {
        Static.global_writer.writer().print("{s}\n", .{msg}) catch unreachable;
        Static.global_writer.flush() catch unreachable;
        std.process.exit(0);
    }
}

// ----- Blargg test rom output -----

pub fn disassemble(opcode: u8, cpu: *const Cpu) !void {
    const Static = struct {
        var buffered_writer: ?std.io.BufferedWriter(4096, std.fs.File.Writer) = null;
    };

    if (Static.buffered_writer == null) {
        Static.buffered_writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    }
    const writer = Static.buffered_writer.?.writer();

    const inst = instructions[opcode];
    try inst.print(writer, opcode, cpu);

    try Static.buffered_writer.?.flush();
}

const instructions = blk: {
    var table: [0x100]Instruction = undefined;
    for (&table, 0..) |*entry, opcode| {
        entry.* = decode(opcode);
    }
    break :blk table;
};

const instructions_cb = blk: {
    var table: [0x100]PrefixCbInstruction = undefined;
    for (&table, 0..) |*entry, opcode| {
        entry.* = decodeCb(opcode);
    }
    break :blk table;
};

fn printRegisters(writer: anytype, cpu: *const Cpu) !void {
    const regs = cpu.regs;
    const z: u8 = if (regs.flags.z) 'z' else '-';
    const n: u8 = if (regs.flags.n) 'n' else '-';
    const h: u8 = if (regs.flags.h) 'h' else '-';
    const c: u8 = if (regs.flags.c) 'c' else '-';
    const a = regs._8.a;
    const bc = regs._16.bc;
    const de = regs._16.de;
    const hl = regs._16.hl;
    const sp = regs._16.sp;

    try writer.print(
        "| flags: {c}{c}{c}{c} | a: ${x:0>2} | bc: ${x:0>4} | de: ${x:0>4} | hl: ${x:0>4} | sp: ${x:0>4} | cycles: {d}\n",
        .{ z, n, h, c, a, bc, de, hl, sp, cpu.bus.cycles },
    );
}

const PrintInfo = struct {
    pc: u16,
    imm: u8,
    imm_s8: i8,
    imm_word: u16,
    reg_c: u8,

    fn init(cpu: *const Cpu) PrintInfo {
        const pc = cpu.regs._16.pc;
        const imm = cpu.bus.peek(pc +% 1);
        const imm_s8: i8 = @bitCast(imm);
        const imm_word = @as(u16, cpu.bus.peek(pc +% 2)) << 8 | imm;
        const reg_c = cpu.regs._8.c;

        return .{
            .pc = pc,
            .imm = imm,
            .imm_s8 = imm_s8,
            .imm_word = imm_word,
            .reg_c = reg_c,
        };
    }
};

const Instruction = struct {
    mnemonic: Mnemonic,
    op0: ?Operand = null,
    op1: ?Operand = null,
    cycles: u8,

    fn print(self: Instruction, writer: anytype, opcode: u8, cpu: *const Cpu) !void {
        const info = PrintInfo.init(cpu);

        var buffer: [512]u8 = undefined;
        var fixed = std.heap.FixedBufferAllocator.init(&buffer);
        const alloc = fixed.allocator();

        if (self.mnemonic == .prefix_cb) {
            const inst_cb = instructions_cb[info.imm];
            try inst_cb.print(writer, alloc, info);
        } else {
            const mnemonic_str = try self.toMnemonicStr(alloc, info);
            try writer.print("${x:0>4}: {x:0>2}    | {s: <20} ", .{ info.pc, opcode, mnemonic_str });
        }

        try printRegisters(writer, cpu);
    }

    fn toMnemonicStr(inst: Instruction, alloc: std.mem.Allocator, info: PrintInfo) ![]u8 {
        const mnemonic = @tagName(inst.mnemonic);
        const op0 = if (inst.op0) |op0| try op0.toStr(alloc, info) else "";
        const op1 = if (inst.op1) |op1| try op1.toStr(alloc, info) else "";

        if (inst.op0 == null and inst.op1 == null) {
            return std.fmt.allocPrint(alloc, "{s}", .{mnemonic});
        }

        if (inst.op0 != null and inst.op1 != null) {
            return std.fmt.allocPrint(alloc, "{s} {s}, {s}", .{ mnemonic, op0, op1 });
        }

        return std.fmt.allocPrint(alloc, "{s} {s}", .{ mnemonic, op0 });
    }
};

const PrefixCbInstruction = struct {
    mnemonic: Mnemonic,
    op: Operand,
    bit: ?u3,
    cycles: u8 = 2,

    fn print(self: PrefixCbInstruction, writer: anytype, alloc: std.mem.Allocator, info: PrintInfo) !void {
        const mnemonic = @tagName(self.mnemonic);
        const bit = if (self.bit) |bit| try std.fmt.allocPrint(alloc, "{d}, ", .{bit}) else "";
        const op = try self.op.toStr(alloc, info);

        const out_str = try std.fmt.allocPrint(alloc, "{s} {s}{s}", .{ mnemonic, bit, op });
        try writer.print("${x:0>4}: cb {x:0>2} | {s: <20} ", .{ info.pc, info.imm, out_str });
    }
};

const Mnemonic = enum {
    nop,
    stop,
    daa,
    cpl,
    scf,
    ccf,
    halt,
    ld,
    inc,
    dec,
    rlca,
    rrca,
    rla,
    rra,
    add,
    adc,
    jr,
    sub,
    sbc,
    @"and",
    xor,
    @"or",
    cp,
    ret,
    pop,
    jp,
    call,
    push,
    rst,
    reti,
    prefix_cb,
    panic,
    di,
    ei,
    rlc,
    rrc,
    rl,
    rr,
    sla,
    sra,
    swap,
    srl,
    bit,
    res,
    set,
};

const Operand = enum {
    af,
    bc,
    de,
    hl,
    sp,
    a,
    b,
    c,
    d,
    e,
    h,
    l,
    @"(hl)",
    @"(bc)",
    @"(de)",
    imm8,
    imm_addr,
    imm16,
    imm_s8,
    cond_nz,
    cond_nc,
    cond_z,
    cond_c,
    @"(hl+)",
    @"(hl-)",
    zero_page,
    zero_page_c,
    sp_imm_s8,
    @"$0000",
    @"$0008",
    @"$0010",
    @"$0018",
    @"$0020",
    @"$0028",
    @"$0030",
    @"$0038",

    // TODO: print cycles per instructions (jp,jr,etc are variable)
    fn toStr(self: Operand, alloc: std.mem.Allocator, info: PrintInfo) ![]const u8 {
        return switch (self) {
            .imm8 => try std.fmt.allocPrint(alloc, "#${x:0>2}", .{info.imm}),
            .imm_addr => try std.fmt.allocPrint(alloc, "(${x:0>4})", .{info.imm_word}),
            .imm16 => try std.fmt.allocPrint(alloc, "${x:0>4}", .{info.imm_word}),
            .imm_s8 => try std.fmt.allocPrint(alloc, "#${x:0>2} ({d})", .{ info.imm, info.imm_s8 }),
            .zero_page => try std.fmt.allocPrint(alloc, "(${x:0>4})", .{0xFF00 | @as(u16, info.imm)}),
            .zero_page_c => try std.fmt.allocPrint(alloc, "(${x:0>4})", .{0xFF00 | @as(u16, info.reg_c)}),
            .sp_imm_s8 => try std.fmt.allocPrint(alloc, "sp+#${x:0>2} ({d})", .{ info.imm, info.imm_s8 }),
            .cond_nz => "nz",
            .cond_nc => "nc",
            .cond_z => "z",
            .cond_c => "c",
            else => @tagName(self),
        };
    }
};

fn decode(comptime opcode: u8) Instruction {
    // See decoding_opcodes.html or
    // https://gb-archive.github.io/salvage/decoding_gbz80_opcodes/Decoding%20Gamboy%20Z80%20Opcodes.html

    const x: u2 = @intCast(opcode >> 6);
    const y: u3 = @intCast((opcode >> 3) & 0x7);
    const z: u3 = @intCast(opcode & 0x7);
    const p: u2 = @intCast(y >> 1);
    const q: bool = y % 2 != 0;

    const cc: [4]Operand = .{ .cond_nz, .cond_z, .cond_nc, .cond_c };
    const rp: [4]Operand = .{ .bc, .de, .hl, .sp };
    const rp2: [4]Operand = .{ .bc, .de, .hl, .af };
    const r: [8]Operand = .{ .b, .c, .d, .e, .h, .l, .@"(hl)", .a };
    const rst: [8]Operand = .{ .@"$0000", .@"$0008", .@"$0010", .@"$0018", .@"$0020", .@"$0028", .@"$0030", .@"$0038" };
    const alu: [8]Mnemonic = .{ .add, .adc, .sub, .sbc, .@"and", .xor, .@"or", .cp };

    const result: Instruction = switch (x) {
        0 => switch (z) {
            0 => switch (y) {
                0 => .{ .mnemonic = .nop, .cycles = 1 },
                1 => .{ .mnemonic = .ld, .op0 = .imm_addr, .op1 = .sp, .cycles = 5 },
                2 => .{ .mnemonic = .stop, .cycles = 1 },
                3 => .{ .mnemonic = .jr, .op0 = .imm_s8, .cycles = 3 },
                4...7 => .{ .mnemonic = .jr, .op0 = cc[y - 4], .op1 = .imm_s8, .cycles = 2 },
            },
            1 => switch (q) {
                false => .{ .mnemonic = .ld, .op0 = rp[p], .op1 = .imm16, .cycles = 3 },
                true => .{ .mnemonic = .add, .op0 = .hl, .op1 = rp[p], .cycles = 2 },
            },
            2 => switch (q) {
                false => switch (p) {
                    0 => .{ .mnemonic = .ld, .op0 = .@"(bc)", .op1 = .a, .cycles = 2 },
                    1 => .{ .mnemonic = .ld, .op0 = .@"(de)", .op1 = .a, .cycles = 2 },
                    2 => .{ .mnemonic = .ld, .op0 = .@"(hl+)", .op1 = .a, .cycles = 2 },
                    3 => .{ .mnemonic = .ld, .op0 = .@"(hl-)", .op1 = .a, .cycles = 2 },
                },
                true => switch (p) {
                    0 => .{ .mnemonic = .ld, .op0 = .a, .op1 = .@"(bc)", .cycles = 2 },
                    1 => .{ .mnemonic = .ld, .op0 = .a, .op1 = .@"(de)", .cycles = 2 },
                    2 => .{ .mnemonic = .ld, .op0 = .a, .op1 = .@"(hl+)", .cycles = 2 },
                    3 => .{ .mnemonic = .ld, .op0 = .a, .op1 = .@"(hl-)", .cycles = 2 },
                },
            },
            3 => switch (q) {
                false => .{ .mnemonic = .inc, .op0 = rp[p], .cycles = 2 },
                true => .{ .mnemonic = .dec, .op0 = rp[p], .cycles = 2 },
            },
            4 => .{ .mnemonic = .inc, .op0 = r[y], .cycles = if (r[y] == .@"(hl)") 3 else 1 },
            5 => .{ .mnemonic = .dec, .op0 = r[y], .cycles = if (r[y] == .@"(hl)") 3 else 1 },
            6 => .{ .mnemonic = .ld, .op0 = r[y], .op1 = .imm8, .cycles = if (r[y] == .@"(hl)") 3 else 2 },
            7 => switch (y) {
                0 => .{ .mnemonic = .rlca, .cycles = 1 },
                1 => .{ .mnemonic = .rrca, .cycles = 1 },
                2 => .{ .mnemonic = .rla, .cycles = 1 },
                3 => .{ .mnemonic = .rra, .cycles = 1 },
                4 => .{ .mnemonic = .daa, .cycles = 1 },
                5 => .{ .mnemonic = .cpl, .cycles = 1 },
                6 => .{ .mnemonic = .scf, .cycles = 1 },
                7 => .{ .mnemonic = .ccf, .cycles = 1 },
            },
        },
        1 => if (z == 6 and y == 6)
            .{ .mnemonic = .halt, .cycles = 1 }
        else
            .{ .mnemonic = .ld, .op0 = r[y], .op1 = r[z], .cycles = if (r[y] == .@"(hl)" or r[z] == .@"(hl)") 2 else 1 },
        2 => .{ .mnemonic = alu[y], .op0 = .a, .op1 = r[z], .cycles = if (r[z] == .@"(hl)") 2 else 1 },
        3 => switch (z) {
            0 => switch (y) {
                0...3 => .{ .mnemonic = .ret, .op0 = cc[y], .cycles = 2 },
                4 => .{ .mnemonic = .ld, .op0 = .zero_page, .op1 = .a, .cycles = 3 },
                5 => .{ .mnemonic = .add, .op0 = .sp, .op1 = .imm_s8, .cycles = 4 },
                6 => .{ .mnemonic = .ld, .op0 = .a, .op1 = .zero_page, .cycles = 3 },
                7 => .{ .mnemonic = .ld, .op0 = .hl, .op1 = .sp_imm_s8, .cycles = 3 },
            },
            1 => switch (q) {
                false => .{ .mnemonic = .pop, .op0 = rp2[p], .cycles = 3 },
                true => switch (p) {
                    0 => .{ .mnemonic = .ret, .cycles = 4 },
                    1 => .{ .mnemonic = .reti, .cycles = 4 },
                    2 => .{ .mnemonic = .jp, .op0 = .hl, .cycles = 1 },
                    3 => .{ .mnemonic = .ld, .op0 = .sp, .op1 = .hl, .cycles = 2 },
                },
            },
            2 => switch (y) {
                0...3 => .{ .mnemonic = .jp, .op0 = cc[y], .op1 = .imm_addr, .cycles = 3 },
                4 => .{ .mnemonic = .ld, .op0 = .zero_page_c, .op1 = .a, .cycles = 2 },
                5 => .{ .mnemonic = .ld, .op0 = .imm_addr, .op1 = .a, .cycles = 4 },
                6 => .{ .mnemonic = .ld, .op0 = .a, .op1 = .zero_page_c, .cycles = 2 },
                7 => .{ .mnemonic = .ld, .op0 = .a, .op1 = .imm_addr, .cycles = 4 },
            },
            3 => switch (y) {
                0 => .{ .mnemonic = .jp, .op0 = .imm_addr, .cycles = 4 },
                1 => .{ .mnemonic = .prefix_cb, .cycles = 2 },
                2...5 => .{ .mnemonic = .panic, .cycles = 1 },
                6 => .{ .mnemonic = .di, .cycles = 1 },
                7 => .{ .mnemonic = .ei, .cycles = 1 },
            },
            4 => switch (y) {
                0...3 => .{ .mnemonic = .call, .op0 = cc[y], .op1 = .imm_addr, .cycles = 3 },
                4...7 => .{ .mnemonic = .panic, .cycles = 1 },
            },
            5 => switch (q) {
                false => .{ .mnemonic = .push, .op0 = rp2[p], .cycles = 4 },
                true => switch (p) {
                    0 => .{ .mnemonic = .call, .op0 = .imm_addr, .cycles = 6 },
                    1...3 => .{ .mnemonic = .panic, .cycles = 1 },
                },
            },
            6 => .{ .mnemonic = alu[y], .op0 = .a, .op1 = .imm8, .cycles = 2 },
            7 => .{ .mnemonic = .rst, .op0 = rst[y], .cycles = 4 },
        },
    };

    return result;
}

fn decodeCb(comptime opcode: u8) PrefixCbInstruction {
    const inst: u2 = @intCast(opcode >> 6);
    const n: u3 = @intCast((opcode >> 3) & 0x7);
    const target: Cpu.CbTarget = @enumFromInt(opcode & 0x07);

    const op: Operand = switch (target) {
        .a => .a,
        .b => .b,
        .c => .c,
        .d => .d,
        .e => .e,
        .h => .h,
        .l => .l,
        .@"(hl)" => .addr_hl,
    };

    const mnemonic: Mnemonic = switch (inst) {
        0 => switch (n) {
            0 => .rlc,
            1 => .rrc,
            2 => .rl,
            3 => .rr,
            4 => .sla,
            5 => .sra,
            6 => .swap,
            7 => .srl,
        },
        1 => .bit,
        2 => .res,
        3 => .set,
    };

    const bit: ?u3 = switch (inst) {
        0 => null,
        else => n,
    };

    return .{
        .mnemonic = mnemonic,
        .op = op,
        .bit = bit,
    };
}
