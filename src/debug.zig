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
        const pc = cpu.regs._16.pc +% 1;
        const imm = cpu.bus.peek(pc);
        const imm_s8: i8 = @bitCast(imm);
        const imm_word = @as(u16, cpu.bus.peek(pc +% 1)) << 8 | imm;
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
    op0: ?Operand,
    op1: ?Operand,
    cycles: u8,

    fn print(self: Instruction, writer: anytype, opcode: u8, cpu: *const Cpu) !void {
        const info = PrintInfo.init(cpu);

        var buffer: [512]u8 = undefined;
        var fixed = std.heap.FixedBufferAllocator.init(&buffer);
        const alloc = fixed.allocator();

        if (self.mnemonic == .prefix_cb) {
            const inst_cb = prefixCb(info.imm);
            try inst_cb.print(writer, alloc, info);
            try printRegisters(writer, cpu);
            return;
        }

        const mnemonic_str = try self.toMnemonicStr(alloc, info);

        try writer.print("${x:0>4}: {x:0>2}    | {s: <20} ", .{ cpu.regs._16.pc, opcode, mnemonic_str });
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
        try writer.print("cb {x:0>2} | {s: <20} ", .{ info.imm, out_str });
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
    rcla,
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
    addr_hl,
    addr_bc,
    addr_de,
    imm8,
    imm_addr,
    imm16,
    imm_s8,
    cond_nz,
    cond_nc,
    cond_z,
    cond_c,
    addr_hli,
    addr_hld,
    zero_page,
    zero_page_c,
    sp_imm_s8,
    @"00",
    @"08",
    @"10",
    @"18",
    @"20",
    @"28",
    @"30",
    @"38",

    // TODO: print cycles per instructions (jp,jr,etc are variable)
    fn toStr(self: Operand, alloc: std.mem.Allocator, info: PrintInfo) ![]const u8 {
        return switch (self) {
            .af, .bc, .de, .hl, .sp, .a, .b, .c, .d, .e, .h, .l => @tagName(self),
            .addr_hl => "(hl)",
            .addr_bc => "(bc)",
            .addr_de => "(de)",
            .imm8 => try std.fmt.allocPrint(alloc, "#${x:0>2}", .{info.imm}),
            .imm_addr => try std.fmt.allocPrint(alloc, "(${x:0>4})", .{info.imm_word}),
            .imm16 => try std.fmt.allocPrint(alloc, "${x:0>4}", .{info.imm_word}),
            .imm_s8 => try std.fmt.allocPrint(alloc, "#${x:0>2} ({d})", .{ info.imm, info.imm_s8 }),
            .cond_nz => "nz",
            .cond_nc => "nc",
            .cond_z => "z",
            .cond_c => "c",
            .addr_hli => "(hl+)",
            .addr_hld => "(hl-)",
            .zero_page => try std.fmt.allocPrint(alloc, "(${x:0>4})", .{0xFF00 | @as(u16, info.imm)}),
            .zero_page_c => try std.fmt.allocPrint(alloc, "(${x:0>4})", .{0xFF00 | @as(u16, info.reg_c)}),
            .sp_imm_s8 => try std.fmt.allocPrint(alloc, "sp+#${x:0>2} ({d})", .{ info.imm, info.imm_s8 }),
            .@"00" => "$0000",
            .@"08" => "$0008",
            .@"10" => "$0010",
            .@"18" => "$0018",
            .@"20" => "$0020",
            .@"28" => "$0028",
            .@"30" => "$0030",
            .@"38" => "$0038",
        };
    }
};

const instructions = blk: {
    var i: [0x100]Instruction = undefined;
    i[0x00] = .{ .mnemonic = .nop, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x01] = .{ .mnemonic = .ld, .op0 = .bc, .op1 = .imm16, .cycles = 3 };
    i[0x02] = .{ .mnemonic = .ld, .op0 = .addr_bc, .op1 = .a, .cycles = 2 };
    i[0x03] = .{ .mnemonic = .inc, .op0 = .bc, .op1 = null, .cycles = 2 };
    i[0x04] = .{ .mnemonic = .inc, .op0 = .b, .op1 = null, .cycles = 1 };
    i[0x05] = .{ .mnemonic = .dec, .op0 = .b, .op1 = null, .cycles = 1 };
    i[0x06] = .{ .mnemonic = .ld, .op0 = .b, .op1 = .imm8, .cycles = 2 };
    i[0x07] = .{ .mnemonic = .rcla, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x08] = .{ .mnemonic = .ld, .op0 = .imm_addr, .op1 = .sp, .cycles = 5 };
    i[0x09] = .{ .mnemonic = .add, .op0 = .hl, .op1 = .bc, .cycles = 2 };
    i[0x0A] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .addr_bc, .cycles = 2 };
    i[0x0B] = .{ .mnemonic = .dec, .op0 = .bc, .op1 = null, .cycles = 2 };
    i[0x0C] = .{ .mnemonic = .inc, .op0 = .c, .op1 = null, .cycles = 1 };
    i[0x0D] = .{ .mnemonic = .dec, .op0 = .c, .op1 = null, .cycles = 1 };
    i[0x0E] = .{ .mnemonic = .ld, .op0 = .c, .op1 = .imm8, .cycles = 2 };
    i[0x0F] = .{ .mnemonic = .rrca, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x10] = .{ .mnemonic = .stop, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x11] = .{ .mnemonic = .ld, .op0 = .de, .op1 = .imm16, .cycles = 3 };
    i[0x12] = .{ .mnemonic = .ld, .op0 = .addr_de, .op1 = .a, .cycles = 2 };
    i[0x13] = .{ .mnemonic = .inc, .op0 = .de, .op1 = null, .cycles = 1 };
    i[0x14] = .{ .mnemonic = .inc, .op0 = .d, .op1 = null, .cycles = 1 };
    i[0x15] = .{ .mnemonic = .dec, .op0 = .d, .op1 = null, .cycles = 1 };
    i[0x16] = .{ .mnemonic = .ld, .op0 = .d, .op1 = .imm8, .cycles = 2 };
    i[0x17] = .{ .mnemonic = .rla, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x18] = .{ .mnemonic = .jr, .op0 = .imm_s8, .op1 = null, .cycles = 3 };
    i[0x19] = .{ .mnemonic = .add, .op0 = .hl, .op1 = .de, .cycles = 2 };
    i[0x1A] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .addr_de, .cycles = 2 };
    i[0x1B] = .{ .mnemonic = .dec, .op0 = .de, .op1 = null, .cycles = 2 };
    i[0x1C] = .{ .mnemonic = .inc, .op0 = .e, .op1 = null, .cycles = 1 };
    i[0x1D] = .{ .mnemonic = .dec, .op0 = .e, .op1 = null, .cycles = 1 };
    i[0x1E] = .{ .mnemonic = .ld, .op0 = .e, .op1 = .imm8, .cycles = 2 };
    i[0x1F] = .{ .mnemonic = .rra, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x20] = .{ .mnemonic = .jr, .op0 = .cond_nz, .op1 = .imm_s8, .cycles = 2 };
    i[0x21] = .{ .mnemonic = .ld, .op0 = .hl, .op1 = .imm16, .cycles = 3 };
    i[0x22] = .{ .mnemonic = .ld, .op0 = .addr_hli, .op1 = .a, .cycles = 2 };
    i[0x23] = .{ .mnemonic = .inc, .op0 = .hl, .op1 = null, .cycles = 2 };
    i[0x24] = .{ .mnemonic = .inc, .op0 = .h, .op1 = null, .cycles = 1 };
    i[0x25] = .{ .mnemonic = .dec, .op0 = .h, .op1 = null, .cycles = 1 };
    i[0x26] = .{ .mnemonic = .ld, .op0 = .h, .op1 = .imm8, .cycles = 2 };
    i[0x27] = .{ .mnemonic = .daa, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x28] = .{ .mnemonic = .jr, .op0 = .cond_z, .op1 = .imm_s8, .cycles = 2 };
    i[0x29] = .{ .mnemonic = .add, .op0 = .hl, .op1 = .hl, .cycles = 2 };
    i[0x2A] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .addr_hli, .cycles = 2 };
    i[0x2B] = .{ .mnemonic = .dec, .op0 = .hl, .op1 = null, .cycles = 2 };
    i[0x2C] = .{ .mnemonic = .inc, .op0 = .l, .op1 = null, .cycles = 1 };
    i[0x2D] = .{ .mnemonic = .dec, .op0 = .l, .op1 = null, .cycles = 1 };
    i[0x2E] = .{ .mnemonic = .ld, .op0 = .l, .op1 = .imm8, .cycles = 2 };
    i[0x2F] = .{ .mnemonic = .cpl, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x30] = .{ .mnemonic = .jr, .op0 = .cond_nc, .op1 = .imm_s8, .cycles = 2 };
    i[0x31] = .{ .mnemonic = .ld, .op0 = .sp, .op1 = .imm16, .cycles = 3 };
    i[0x32] = .{ .mnemonic = .ld, .op0 = .addr_hld, .op1 = .a, .cycles = 2 };
    i[0x33] = .{ .mnemonic = .inc, .op0 = .sp, .op1 = null, .cycles = 2 };
    i[0x34] = .{ .mnemonic = .inc, .op0 = .addr_hl, .op1 = null, .cycles = 3 };
    i[0x35] = .{ .mnemonic = .dec, .op0 = .addr_hl, .op1 = null, .cycles = 3 };
    i[0x36] = .{ .mnemonic = .ld, .op0 = .addr_hl, .op1 = .imm8, .cycles = 3 };
    i[0x37] = .{ .mnemonic = .scf, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x38] = .{ .mnemonic = .jr, .op0 = .cond_c, .op1 = .imm_s8, .cycles = 2 };
    i[0x39] = .{ .mnemonic = .add, .op0 = .hl, .op1 = .sp, .cycles = 2 };
    i[0x3A] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .addr_hld, .cycles = 2 };
    i[0x3B] = .{ .mnemonic = .dec, .op0 = .sp, .op1 = null, .cycles = 2 };
    i[0x3C] = .{ .mnemonic = .inc, .op0 = .a, .op1 = null, .cycles = 1 };
    i[0x3D] = .{ .mnemonic = .dec, .op0 = .a, .op1 = null, .cycles = 1 };
    i[0x3E] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .imm8, .cycles = 2 };
    i[0x3F] = .{ .mnemonic = .ccf, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x40] = .{ .mnemonic = .ld, .op0 = .b, .op1 = .b, .cycles = 1 };
    i[0x41] = .{ .mnemonic = .ld, .op0 = .b, .op1 = .c, .cycles = 1 };
    i[0x42] = .{ .mnemonic = .ld, .op0 = .b, .op1 = .d, .cycles = 1 };
    i[0x43] = .{ .mnemonic = .ld, .op0 = .b, .op1 = .e, .cycles = 1 };
    i[0x44] = .{ .mnemonic = .ld, .op0 = .b, .op1 = .h, .cycles = 1 };
    i[0x45] = .{ .mnemonic = .ld, .op0 = .b, .op1 = .l, .cycles = 1 };
    i[0x46] = .{ .mnemonic = .ld, .op0 = .b, .op1 = .addr_hl, .cycles = 2 };
    i[0x47] = .{ .mnemonic = .ld, .op0 = .b, .op1 = .a, .cycles = 1 };
    i[0x48] = .{ .mnemonic = .ld, .op0 = .c, .op1 = .b, .cycles = 1 };
    i[0x49] = .{ .mnemonic = .ld, .op0 = .c, .op1 = .c, .cycles = 1 };
    i[0x4A] = .{ .mnemonic = .ld, .op0 = .c, .op1 = .d, .cycles = 1 };
    i[0x4B] = .{ .mnemonic = .ld, .op0 = .c, .op1 = .e, .cycles = 1 };
    i[0x4C] = .{ .mnemonic = .ld, .op0 = .c, .op1 = .h, .cycles = 1 };
    i[0x4D] = .{ .mnemonic = .ld, .op0 = .c, .op1 = .l, .cycles = 1 };
    i[0x4E] = .{ .mnemonic = .ld, .op0 = .c, .op1 = .addr_hl, .cycles = 2 };
    i[0x4F] = .{ .mnemonic = .ld, .op0 = .c, .op1 = .a, .cycles = 1 };
    i[0x50] = .{ .mnemonic = .ld, .op0 = .d, .op1 = .b, .cycles = 1 };
    i[0x51] = .{ .mnemonic = .ld, .op0 = .d, .op1 = .c, .cycles = 1 };
    i[0x52] = .{ .mnemonic = .ld, .op0 = .d, .op1 = .d, .cycles = 1 };
    i[0x53] = .{ .mnemonic = .ld, .op0 = .d, .op1 = .e, .cycles = 1 };
    i[0x54] = .{ .mnemonic = .ld, .op0 = .d, .op1 = .h, .cycles = 1 };
    i[0x55] = .{ .mnemonic = .ld, .op0 = .d, .op1 = .l, .cycles = 1 };
    i[0x56] = .{ .mnemonic = .ld, .op0 = .d, .op1 = .addr_hl, .cycles = 2 };
    i[0x57] = .{ .mnemonic = .ld, .op0 = .d, .op1 = .a, .cycles = 1 };
    i[0x58] = .{ .mnemonic = .ld, .op0 = .e, .op1 = .b, .cycles = 1 };
    i[0x59] = .{ .mnemonic = .ld, .op0 = .e, .op1 = .c, .cycles = 1 };
    i[0x5A] = .{ .mnemonic = .ld, .op0 = .e, .op1 = .d, .cycles = 1 };
    i[0x5B] = .{ .mnemonic = .ld, .op0 = .e, .op1 = .e, .cycles = 1 };
    i[0x5C] = .{ .mnemonic = .ld, .op0 = .e, .op1 = .h, .cycles = 1 };
    i[0x5D] = .{ .mnemonic = .ld, .op0 = .e, .op1 = .l, .cycles = 1 };
    i[0x5E] = .{ .mnemonic = .ld, .op0 = .e, .op1 = .addr_hl, .cycles = 2 };
    i[0x5F] = .{ .mnemonic = .ld, .op0 = .e, .op1 = .a, .cycles = 1 };
    i[0x60] = .{ .mnemonic = .ld, .op0 = .h, .op1 = .b, .cycles = 1 };
    i[0x61] = .{ .mnemonic = .ld, .op0 = .h, .op1 = .c, .cycles = 1 };
    i[0x62] = .{ .mnemonic = .ld, .op0 = .h, .op1 = .d, .cycles = 1 };
    i[0x63] = .{ .mnemonic = .ld, .op0 = .h, .op1 = .e, .cycles = 1 };
    i[0x64] = .{ .mnemonic = .ld, .op0 = .h, .op1 = .h, .cycles = 1 };
    i[0x65] = .{ .mnemonic = .ld, .op0 = .h, .op1 = .l, .cycles = 1 };
    i[0x66] = .{ .mnemonic = .ld, .op0 = .h, .op1 = .addr_hl, .cycles = 2 };
    i[0x67] = .{ .mnemonic = .ld, .op0 = .h, .op1 = .a, .cycles = 1 };
    i[0x68] = .{ .mnemonic = .ld, .op0 = .l, .op1 = .b, .cycles = 1 };
    i[0x69] = .{ .mnemonic = .ld, .op0 = .l, .op1 = .c, .cycles = 1 };
    i[0x6A] = .{ .mnemonic = .ld, .op0 = .l, .op1 = .d, .cycles = 1 };
    i[0x6B] = .{ .mnemonic = .ld, .op0 = .l, .op1 = .e, .cycles = 1 };
    i[0x6C] = .{ .mnemonic = .ld, .op0 = .l, .op1 = .h, .cycles = 1 };
    i[0x6D] = .{ .mnemonic = .ld, .op0 = .l, .op1 = .l, .cycles = 1 };
    i[0x6E] = .{ .mnemonic = .ld, .op0 = .l, .op1 = .addr_hl, .cycles = 2 };
    i[0x6F] = .{ .mnemonic = .ld, .op0 = .l, .op1 = .a, .cycles = 1 };
    i[0x70] = .{ .mnemonic = .ld, .op0 = .addr_hl, .op1 = .b, .cycles = 2 };
    i[0x71] = .{ .mnemonic = .ld, .op0 = .addr_hl, .op1 = .c, .cycles = 2 };
    i[0x72] = .{ .mnemonic = .ld, .op0 = .addr_hl, .op1 = .d, .cycles = 2 };
    i[0x73] = .{ .mnemonic = .ld, .op0 = .addr_hl, .op1 = .e, .cycles = 2 };
    i[0x74] = .{ .mnemonic = .ld, .op0 = .addr_hl, .op1 = .h, .cycles = 2 };
    i[0x75] = .{ .mnemonic = .ld, .op0 = .addr_hl, .op1 = .l, .cycles = 2 };
    i[0x76] = .{ .mnemonic = .halt, .op0 = null, .op1 = null, .cycles = 1 };
    i[0x77] = .{ .mnemonic = .ld, .op0 = .addr_hl, .op1 = .a, .cycles = 2 };
    i[0x78] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .b, .cycles = 1 };
    i[0x79] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .c, .cycles = 1 };
    i[0x7A] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .d, .cycles = 1 };
    i[0x7B] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .e, .cycles = 1 };
    i[0x7C] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .h, .cycles = 1 };
    i[0x7D] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .l, .cycles = 1 };
    i[0x7E] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .addr_hl, .cycles = 2 };
    i[0x7F] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .a, .cycles = 1 };
    i[0x80] = .{ .mnemonic = .add, .op0 = .a, .op1 = .b, .cycles = 1 };
    i[0x81] = .{ .mnemonic = .add, .op0 = .a, .op1 = .c, .cycles = 1 };
    i[0x82] = .{ .mnemonic = .add, .op0 = .a, .op1 = .d, .cycles = 1 };
    i[0x83] = .{ .mnemonic = .add, .op0 = .a, .op1 = .e, .cycles = 1 };
    i[0x84] = .{ .mnemonic = .add, .op0 = .a, .op1 = .h, .cycles = 1 };
    i[0x85] = .{ .mnemonic = .add, .op0 = .a, .op1 = .l, .cycles = 1 };
    i[0x86] = .{ .mnemonic = .add, .op0 = .a, .op1 = .addr_hl, .cycles = 2 };
    i[0x87] = .{ .mnemonic = .add, .op0 = .a, .op1 = .a, .cycles = 1 };
    i[0x88] = .{ .mnemonic = .adc, .op0 = .a, .op1 = .b, .cycles = 1 };
    i[0x89] = .{ .mnemonic = .adc, .op0 = .a, .op1 = .c, .cycles = 1 };
    i[0x8A] = .{ .mnemonic = .adc, .op0 = .a, .op1 = .d, .cycles = 1 };
    i[0x8B] = .{ .mnemonic = .adc, .op0 = .a, .op1 = .e, .cycles = 1 };
    i[0x8C] = .{ .mnemonic = .adc, .op0 = .a, .op1 = .h, .cycles = 1 };
    i[0x8D] = .{ .mnemonic = .adc, .op0 = .a, .op1 = .l, .cycles = 1 };
    i[0x8E] = .{ .mnemonic = .adc, .op0 = .a, .op1 = .addr_hl, .cycles = 2 };
    i[0x8F] = .{ .mnemonic = .adc, .op0 = .a, .op1 = .a, .cycles = 1 };
    i[0x90] = .{ .mnemonic = .sub, .op0 = .a, .op1 = .b, .cycles = 1 };
    i[0x91] = .{ .mnemonic = .sub, .op0 = .a, .op1 = .c, .cycles = 1 };
    i[0x92] = .{ .mnemonic = .sub, .op0 = .a, .op1 = .d, .cycles = 1 };
    i[0x93] = .{ .mnemonic = .sub, .op0 = .a, .op1 = .e, .cycles = 1 };
    i[0x94] = .{ .mnemonic = .sub, .op0 = .a, .op1 = .h, .cycles = 1 };
    i[0x95] = .{ .mnemonic = .sub, .op0 = .a, .op1 = .l, .cycles = 1 };
    i[0x96] = .{ .mnemonic = .sub, .op0 = .a, .op1 = .addr_hl, .cycles = 2 };
    i[0x97] = .{ .mnemonic = .sub, .op0 = .a, .op1 = .a, .cycles = 1 };
    i[0x98] = .{ .mnemonic = .sbc, .op0 = .a, .op1 = .b, .cycles = 1 };
    i[0x99] = .{ .mnemonic = .sbc, .op0 = .a, .op1 = .c, .cycles = 1 };
    i[0x9A] = .{ .mnemonic = .sbc, .op0 = .a, .op1 = .d, .cycles = 1 };
    i[0x9B] = .{ .mnemonic = .sbc, .op0 = .a, .op1 = .e, .cycles = 1 };
    i[0x9C] = .{ .mnemonic = .sbc, .op0 = .a, .op1 = .h, .cycles = 1 };
    i[0x9D] = .{ .mnemonic = .sbc, .op0 = .a, .op1 = .l, .cycles = 1 };
    i[0x9E] = .{ .mnemonic = .sbc, .op0 = .a, .op1 = .addr_hl, .cycles = 2 };
    i[0x9F] = .{ .mnemonic = .sbc, .op0 = .a, .op1 = .a, .cycles = 1 };
    i[0xA0] = .{ .mnemonic = .@"and", .op0 = .a, .op1 = .b, .cycles = 1 };
    i[0xA1] = .{ .mnemonic = .@"and", .op0 = .a, .op1 = .c, .cycles = 1 };
    i[0xA2] = .{ .mnemonic = .@"and", .op0 = .a, .op1 = .d, .cycles = 1 };
    i[0xA3] = .{ .mnemonic = .@"and", .op0 = .a, .op1 = .e, .cycles = 1 };
    i[0xA4] = .{ .mnemonic = .@"and", .op0 = .a, .op1 = .h, .cycles = 1 };
    i[0xA5] = .{ .mnemonic = .@"and", .op0 = .a, .op1 = .l, .cycles = 1 };
    i[0xA6] = .{ .mnemonic = .@"and", .op0 = .a, .op1 = .addr_hl, .cycles = 2 };
    i[0xA7] = .{ .mnemonic = .@"and", .op0 = .a, .op1 = .a, .cycles = 1 };
    i[0xA8] = .{ .mnemonic = .xor, .op0 = .a, .op1 = .b, .cycles = 1 };
    i[0xA9] = .{ .mnemonic = .xor, .op0 = .a, .op1 = .c, .cycles = 1 };
    i[0xAA] = .{ .mnemonic = .xor, .op0 = .a, .op1 = .d, .cycles = 1 };
    i[0xAB] = .{ .mnemonic = .xor, .op0 = .a, .op1 = .e, .cycles = 1 };
    i[0xAC] = .{ .mnemonic = .xor, .op0 = .a, .op1 = .h, .cycles = 1 };
    i[0xAD] = .{ .mnemonic = .xor, .op0 = .a, .op1 = .l, .cycles = 1 };
    i[0xAE] = .{ .mnemonic = .xor, .op0 = .a, .op1 = .addr_hl, .cycles = 2 };
    i[0xAF] = .{ .mnemonic = .xor, .op0 = .a, .op1 = .a, .cycles = 1 };
    i[0xB0] = .{ .mnemonic = .@"or", .op0 = .a, .op1 = .b, .cycles = 1 };
    i[0xB1] = .{ .mnemonic = .@"or", .op0 = .a, .op1 = .c, .cycles = 1 };
    i[0xB2] = .{ .mnemonic = .@"or", .op0 = .a, .op1 = .d, .cycles = 1 };
    i[0xB3] = .{ .mnemonic = .@"or", .op0 = .a, .op1 = .e, .cycles = 1 };
    i[0xB4] = .{ .mnemonic = .@"or", .op0 = .a, .op1 = .h, .cycles = 1 };
    i[0xB5] = .{ .mnemonic = .@"or", .op0 = .a, .op1 = .l, .cycles = 1 };
    i[0xB6] = .{ .mnemonic = .@"or", .op0 = .a, .op1 = .addr_hl, .cycles = 2 };
    i[0xB7] = .{ .mnemonic = .@"or", .op0 = .a, .op1 = .a, .cycles = 1 };
    i[0xB8] = .{ .mnemonic = .cp, .op0 = .a, .op1 = .b, .cycles = 1 };
    i[0xB9] = .{ .mnemonic = .cp, .op0 = .a, .op1 = .c, .cycles = 1 };
    i[0xBA] = .{ .mnemonic = .cp, .op0 = .a, .op1 = .d, .cycles = 1 };
    i[0xBB] = .{ .mnemonic = .cp, .op0 = .a, .op1 = .e, .cycles = 1 };
    i[0xBC] = .{ .mnemonic = .cp, .op0 = .a, .op1 = .h, .cycles = 1 };
    i[0xBD] = .{ .mnemonic = .cp, .op0 = .a, .op1 = .l, .cycles = 1 };
    i[0xBE] = .{ .mnemonic = .cp, .op0 = .a, .op1 = .addr_hl, .cycles = 2 };
    i[0xBF] = .{ .mnemonic = .cp, .op0 = .a, .op1 = .a, .cycles = 1 };
    i[0xC0] = .{ .mnemonic = .ret, .op0 = .cond_nz, .op1 = null, .cycles = 2 };
    i[0xC1] = .{ .mnemonic = .pop, .op0 = .bc, .op1 = null, .cycles = 3 };
    i[0xC2] = .{ .mnemonic = .jp, .op0 = .cond_nz, .op1 = .imm_addr, .cycles = 3 };
    i[0xC3] = .{ .mnemonic = .jp, .op0 = .imm_addr, .op1 = null, .cycles = 4 };
    i[0xC4] = .{ .mnemonic = .call, .op0 = .cond_nz, .op1 = .imm_addr, .cycles = 3 };
    i[0xC5] = .{ .mnemonic = .push, .op0 = .bc, .op1 = null, .cycles = 4 };
    i[0xC6] = .{ .mnemonic = .add, .op0 = .a, .op1 = .imm8, .cycles = 2 };
    i[0xC7] = .{ .mnemonic = .rst, .op0 = .@"00", .op1 = null, .cycles = 4 };
    i[0xC8] = .{ .mnemonic = .ret, .op0 = .cond_z, .op1 = null, .cycles = 2 };
    i[0xC9] = .{ .mnemonic = .ret, .op0 = null, .op1 = null, .cycles = 4 };
    i[0xCA] = .{ .mnemonic = .jp, .op0 = .cond_z, .op1 = .imm_addr, .cycles = 3 };
    i[0xCB] = .{ .mnemonic = .prefix_cb, .op0 = null, .op1 = null, .cycles = 2 };
    i[0xCC] = .{ .mnemonic = .call, .op0 = .cond_z, .op1 = .imm_addr, .cycles = 3 };
    i[0xCD] = .{ .mnemonic = .call, .op0 = .imm_addr, .op1 = null, .cycles = 6 };
    i[0xCE] = .{ .mnemonic = .adc, .op0 = .a, .op1 = .imm8, .cycles = 2 };
    i[0xCF] = .{ .mnemonic = .rst, .op0 = .@"08", .op1 = null, .cycles = 4 };
    i[0xD0] = .{ .mnemonic = .ret, .op0 = .cond_nc, .op1 = null, .cycles = 2 };
    i[0xD1] = .{ .mnemonic = .pop, .op0 = .de, .op1 = null, .cycles = 3 };
    i[0xD2] = .{ .mnemonic = .jp, .op0 = .cond_nc, .op1 = .imm_addr, .cycles = 3 };
    i[0xD3] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xD4] = .{ .mnemonic = .call, .op0 = .cond_nc, .op1 = .imm_addr, .cycles = 3 };
    i[0xD5] = .{ .mnemonic = .push, .op0 = .de, .op1 = null, .cycles = 4 };
    i[0xD6] = .{ .mnemonic = .sub, .op0 = .a, .op1 = .imm8, .cycles = 2 };
    i[0xD7] = .{ .mnemonic = .rst, .op0 = .@"10", .op1 = null, .cycles = 4 };
    i[0xD8] = .{ .mnemonic = .ret, .op0 = .cond_c, .op1 = null, .cycles = 2 };
    i[0xD9] = .{ .mnemonic = .reti, .op0 = null, .op1 = null, .cycles = 4 };
    i[0xDA] = .{ .mnemonic = .jp, .op0 = .cond_c, .op1 = .imm_addr, .cycles = 3 };
    i[0xDB] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xDC] = .{ .mnemonic = .call, .op0 = .cond_c, .op1 = .imm_addr, .cycles = 3 };
    i[0xDD] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xDE] = .{ .mnemonic = .sbc, .op0 = .a, .op1 = .imm8, .cycles = 2 };
    i[0xDF] = .{ .mnemonic = .rst, .op0 = .@"18", .op1 = null, .cycles = 4 };
    i[0xE0] = .{ .mnemonic = .ld, .op0 = .zero_page, .op1 = .a, .cycles = 3 };
    i[0xE1] = .{ .mnemonic = .pop, .op0 = .hl, .op1 = null, .cycles = 3 };
    i[0xE2] = .{ .mnemonic = .ld, .op0 = .zero_page_c, .op1 = .a, .cycles = 2 };
    i[0xE3] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xE4] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xE5] = .{ .mnemonic = .push, .op0 = .hl, .op1 = null, .cycles = 4 };
    i[0xE6] = .{ .mnemonic = .@"and", .op0 = .a, .op1 = .imm8, .cycles = 2 };
    i[0xE7] = .{ .mnemonic = .rst, .op0 = .@"20", .op1 = null, .cycles = 4 };
    i[0xE8] = .{ .mnemonic = .add, .op0 = .sp, .op1 = .imm_s8, .cycles = 4 };
    i[0xE9] = .{ .mnemonic = .jp, .op0 = .hl, .op1 = null, .cycles = 1 };
    i[0xEA] = .{ .mnemonic = .ld, .op0 = .imm_addr, .op1 = .a, .cycles = 4 };
    i[0xEB] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xEC] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xED] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xEE] = .{ .mnemonic = .xor, .op0 = .a, .op1 = .imm8, .cycles = 2 };
    i[0xEF] = .{ .mnemonic = .rst, .op0 = .@"28", .op1 = null, .cycles = 4 };
    i[0xF0] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .zero_page, .cycles = 3 };
    i[0xF1] = .{ .mnemonic = .pop, .op0 = .af, .op1 = null, .cycles = 3 };
    i[0xF2] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .zero_page_c, .cycles = 2 };
    i[0xF3] = .{ .mnemonic = .di, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xF4] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xF5] = .{ .mnemonic = .push, .op0 = .af, .op1 = null, .cycles = 4 };
    i[0xF6] = .{ .mnemonic = .@"or", .op0 = .a, .op1 = .imm8, .cycles = 2 };
    i[0xF7] = .{ .mnemonic = .rst, .op0 = .@"30", .op1 = null, .cycles = 4 };
    i[0xF8] = .{ .mnemonic = .ld, .op0 = .hl, .op1 = .sp_imm_s8, .cycles = 3 };
    i[0xF9] = .{ .mnemonic = .ld, .op0 = .sp, .op1 = .hl, .cycles = 2 };
    i[0xFA] = .{ .mnemonic = .ld, .op0 = .a, .op1 = .imm_addr, .cycles = 4 };
    i[0xFB] = .{ .mnemonic = .ei, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xFC] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xFD] = .{ .mnemonic = .panic, .op0 = null, .op1 = null, .cycles = 1 };
    i[0xFE] = .{ .mnemonic = .cp, .op0 = .a, .op1 = .imm8, .cycles = 2 };
    i[0xFF] = .{ .mnemonic = .rst, .op0 = .@"38", .op1 = null, .cycles = 4 };
    break :blk i;
};

fn prefixCb(opcode: u8) PrefixCbInstruction {
    const low: u4 = @truncate(opcode & 0x0F);

    const op: Operand = switch (low) {
        0x07, 0x0F => .a,
        0x00, 0x08 => .b,
        0x01, 0x09 => .c,
        0x02, 0x0A => .d,
        0x03, 0x0B => .e,
        0x04, 0x0C => .h,
        0x05, 0x0D => .l,
        0x06, 0x0E => .addr_hl,
    };

    const mnemonic: Mnemonic = switch (opcode) {
        0x00...0x07 => .rlc,
        0x08...0x0F => .rrc,
        0x10...0x17 => .rl,
        0x18...0x1F => .rr,
        0x20...0x27 => .sla,
        0x28...0x2F => .sra,
        0x30...0x37 => .swap,
        0x38...0x3F => .srl,
        0x40...0x7F => .bit,
        0x80...0xBF => .res,
        0xC0...0xFF => .set,
    };

    const bit: ?u3 = switch (opcode) {
        0x40...0x47, 0x80...0x87, 0xC0...0xC7 => 0,
        0x48...0x4F, 0x88...0x8F, 0xC8...0xCF => 1,
        0x50...0x57, 0x90...0x97, 0xD0...0xD7 => 2,
        0x58...0x5F, 0x98...0x9F, 0xD8...0xDF => 3,
        0x60...0x67, 0xA0...0xA7, 0xE0...0xE7 => 4,
        0x68...0x6F, 0xA8...0xAF, 0xE8...0xEF => 5,
        0x70...0x77, 0xB0...0xB7, 0xF0...0xF7 => 6,
        0x78...0x7F, 0xB8...0xBF, 0xF8...0xFF => 7,
        else => null,
    };

    return .{
        .mnemonic = mnemonic,
        .op = op,
        .bit = bit,
    };
}
