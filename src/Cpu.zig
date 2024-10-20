const std = @import("std");
const registers = @import("cpu/registers.zig");
const Bus = @import("Bus.zig");

const Cpu = @This();

pub const Registers = registers.Registers;
pub const Flags = registers.Flags;
pub const Target = @import("cpu/target.zig").Target;

const JumpCond = enum { c, z, nc, nz, always };
const RotateOp = enum { rl, rlc, rr, rrc };

regs: Registers,
bus: Bus,
ime_toggle: bool,
ime: bool,
halted: bool,

pub fn init(rom: []const u8) Cpu {
    return .{
        .regs = .init,
        .bus = Bus.init(rom),
        .ime_toggle = false,
        .ime = false,
        .halted = false,
    };
}

pub fn step(self: *Cpu) void {
    const ime = self.ime;
    _ = ime; // autofix

    if (self.ime_toggle) {
        self.ime = !self.ime;
        self.ime_toggle = false;
    }

    const opcode = self.read8();
    self.execute(opcode);
}

pub fn read8(self: *Cpu) u8 {
    const value = self.bus.read(self.regs._16.pc);
    self.regs._16.pc +%= 1;
    return value;
}

pub fn read16(self: *Cpu) u16 {
    const lo: u16 = self.read8();
    const hi: u16 = self.read8();
    return hi << 8 | lo;
}

fn shouldJump(flags: Flags, comptime cond: JumpCond) bool {
    return switch (cond) {
        .c => flags.c,
        .z => flags.z,
        .nc => !flags.c,
        .nz => !flags.z,
        .always => true,
    };
}

fn jump(self: *Cpu, addr: u16) void {
    self.regs._16.pc = addr;
    self.bus.tick();
}

fn jumpRelative(self: *Cpu, offset: i8) void {
    const offset16: u16 = @bitCast(@as(i16, offset));
    self.jump(self.regs._16.pc +% offset16);
}

fn stackPush(self: *Cpu, value: u16) void {
    self.bus.tick();

    const bytes = std.mem.toBytes(value);
    const hi = bytes[1];
    const lo = bytes[0];

    self.regs._16.sp -%= 1;
    self.bus.write(self.regs._16.sp, hi);
    self.regs._16.sp -%= 1;
    self.bus.write(self.regs._16.sp, lo);
}

fn stackPop(self: *Cpu) u16 {
    const lo = self.bus.read(self.regs._16.sp);
    self.regs._16.sp +%= 1;
    const hi = self.bus.read(self.regs._16.sp);
    self.regs._16.sp +%= 1;

    const value = std.mem.bytesAsValue(u16, &.{ lo, hi });
    return value.*;
}

fn ld(self: *Cpu, comptime dst: Target, comptime src: Target) void {
    const value = src.getValue(self);
    dst.setValue(self, value);
}

fn ld16(self: *Cpu, comptime dst: Target) void {
    const value = self.read16();
    dst.setValue16(self, value);
}

fn ldAbsSp(self: *Cpu) void {
    const addr = self.read16();
    const sp = std.mem.toBytes(self.regs._16.sp);
    self.bus.write(addr, sp[0]);
    self.bus.write(addr +% 1, sp[1]);
}

fn ldHlSpImm(self: *Cpu) void {
    const signed: i16 = @as(i8, @bitCast(self.read8()));
    const offset: u16 = @bitCast(signed);
    const sp = self.regs._16.sp;

    self.regs._16.hl = sp +% offset;

    const carry = (sp & 0xFF) + (offset & 0xFF) > 0xFF;
    const half = (sp & 0xF) + (offset & 0xF) > 0xF;
    self.regs.flags.c = carry;
    self.regs.flags.h = half;
    self.regs.flags.n = false;
    self.regs.flags.z = false;

    self.bus.tick();
}

fn ldSpHl(self: *Cpu) void {
    self.regs._16.sp = self.regs._16.hl;
    self.bus.tick();
}

fn aluAdd(self: *Cpu, value: u8, cy: u1) void {
    const a = self.regs._8.a;
    const result = @as(u16, a) + value + cy;

    self.regs.flags.c = result > 0xFF;
    self.regs.flags.h = (a & 0x0F) + (value & 0x0F) + cy > 0x0F;
    self.regs.flags.n = false;
    self.regs.flags.z = result & 0xFF == 0;

    self.regs._8.a = @truncate(result);
}

fn add(self: *Cpu, comptime src: Target) void {
    const value = src.getValue(self);
    self.aluAdd(value, 0);
}

fn adc(self: *Cpu, comptime src: Target) void {
    const value = src.getValue(self);
    self.aluAdd(value, @intFromBool(self.regs.flags.c));
}

fn addHl(self: *Cpu, comptime dst: Target) void {
    const value = dst.getValue16(self);
    const hl = self.regs._16.hl;
    const result, const carry = @addWithOverflow(hl, value);

    self.regs.flags.c = carry != 0;
    self.regs.flags.h = (hl & 0x0FFF) + (value & 0x0FFF) > 0x0FFF;
    self.regs.flags.n = false;

    self.regs._16.hl = result;

    self.bus.tick();
}

fn addSpImm(self: *Cpu) void {
    const signed: i16 = @as(i8, @bitCast(self.read8()));
    const value: u16 = @bitCast(signed);
    const sp = self.regs._16.sp;

    self.regs.flags.c = (sp & 0x00FF) + (value & 0x00FF) > 0x00FF;
    self.regs.flags.h = (sp & 0x000F) + (value & 0x000F) > 0x000F;
    self.regs.flags.n = false;
    self.regs.flags.z = false;

    self.regs._16.sp = sp +% value;

    self.bus.tick();
    self.bus.tick();
}

fn aluSub(self: *Cpu, value: u8, cy: u1) u8 {
    const a = self.regs._8.a;
    const result = a -% value -% cy;

    self.regs.flags.c = @as(u16, a) < @as(u16, value) + cy;
    self.regs.flags.h = (a & 0x0F) < (value & 0x0F) + cy;
    self.regs.flags.n = true;
    self.regs.flags.z = result == 0;

    return result;
}

fn sub(self: *Cpu, comptime src: Target) void {
    const value = src.getValue(self);
    const result = self.aluSub(value, 0);
    self.regs._8.a = result;
}

fn sbc(self: *Cpu, comptime src: Target) void {
    const value = src.getValue(self);
    const result = self.aluSub(value, @intFromBool(self.regs.flags.c));
    self.regs._8.a = result;
}

fn cp(self: *Cpu, comptime src: Target) void {
    const value = src.getValue(self);
    _ = self.aluSub(value, 0);
}

fn bitAnd(self: *Cpu, comptime src: Target) void {
    const value = src.getValue(self);
    const result = self.regs._8.a & value;

    self.regs.flags.c = false;
    self.regs.flags.h = true;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;

    self.regs._8.a = result;
}

fn bitXor(self: *Cpu, comptime src: Target) void {
    const value = src.getValue(self);
    const result = self.regs._8.a ^ value;

    self.regs.flags.c = false;
    self.regs.flags.h = false;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;

    self.regs._8.a = result;
}

fn bitOr(self: *Cpu, comptime src: Target) void {
    const value = src.getValue(self);
    const result = self.regs._8.a | value;

    self.regs.flags.c = false;
    self.regs.flags.h = false;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;

    self.regs._8.a = result;
}

fn inc(self: *Cpu, comptime target: Target) void {
    const value = target.getValue(self);
    const result = value +% 1;

    self.regs.flags.h = value & 0x0F == 0x0F;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;

    target.setValue(self, result);
}

fn inc16(self: *Cpu, comptime target: Target) void {
    const value = target.getValue16(self);
    target.setValue16(self, value +% 1);
    self.bus.tick();
}

fn dec(self: *Cpu, comptime target: Target) void {
    const value = target.getValue(self);
    const result = value -% 1;

    self.regs.flags.h = value & 0x0F == 0x00;
    self.regs.flags.n = true;
    self.regs.flags.z = result == 0;

    target.setValue(self, result);
}

fn dec16(self: *Cpu, comptime target: Target) void {
    const value = target.getValue16(self);
    target.setValue16(self, value -% 1);
    self.bus.tick();
}

fn jr(self: *Cpu, comptime cond: JumpCond) void {
    const offset: i8 = @bitCast(self.read8());
    if (shouldJump(self.regs.flags, cond)) {
        self.jumpRelative(offset);
    }
}

fn jp(self: *Cpu, comptime cond: JumpCond) void {
    const addr = self.read16();
    if (shouldJump(self.regs.flags, cond)) {
        self.jump(addr);
    }
}

fn jpHl(self: *Cpu) void {
    self.regs._16.pc = self.regs._16.hl;
}

fn daa(self: *Cpu) void {
    var adjust: u8 = 0;
    var carry = false;

    var a = self.regs._8.a;
    const c = self.regs.flags.c;
    const n = self.regs.flags.n;
    const h = self.regs.flags.h;

    if (h or (!n and a & 0x0F > 0x09)) {
        adjust |= 0x06;
    }

    if (c or (!n and a > 0x99)) {
        adjust |= 0x60;
        carry = true;
    }

    if (n) {
        a -%= adjust;
    } else {
        a +%= adjust;
    }

    self.regs._8.a = a;
    self.regs.flags.c = carry;
    self.regs.flags.z = a == 0;
    self.regs.flags.h = false;
}

fn scf(self: *Cpu) void {
    self.regs.flags.c = true;
    self.regs.flags.h = false;
    self.regs.flags.n = false;
}

fn cpl(self: *Cpu) void {
    self.regs._8.a = ~self.regs._8.a;

    self.regs.flags.h = true;
    self.regs.flags.n = true;
}

fn ccf(self: *Cpu) void {
    self.regs.flags.c = !self.regs.flags.c;
    self.regs.flags.h = false;
    self.regs.flags.n = false;
}

fn push(self: *Cpu, comptime target: Target) void {
    const value = target.getValue16(self);
    self.stackPush(value);
}

fn pop(self: *Cpu, comptime target: Target) void {
    const value = self.stackPop();
    target.setValue16(self, value);

    // Clear unused flags bits; they didn't exist on real hardware
    if (target == .af) self.regs.flags._unused = 0;
}

fn call(self: *Cpu, comptime cond: JumpCond) void {
    const addr = self.read16();
    if (shouldJump(self.regs.flags, cond)) {
        self.stackPush(self.regs._16.pc);
        self.regs._16.pc = addr;
    }
}

fn ret(self: *Cpu, comptime cond: JumpCond) void {
    if (cond != .always) self.bus.tick();
    if (shouldJump(self.regs.flags, cond)) {
        const addr = self.stackPop();
        self.jump(addr);
    }
}

fn reti(self: *Cpu) void {
    self.ret(.always);
    self.ime = true;
}

fn rst(self: *Cpu, comptime addr: u8) void {
    self.stackPush(self.regs._16.pc);
    self.regs._16.pc = addr;
}

fn halt(self: *Cpu) void {
    self.bus.tick();
    self.halted = true;
}

fn ei(self: *Cpu) void {
    if (!self.ime) {
        self.ime_toggle = true;
    }
}

fn di(self: *Cpu) void {
    self.ime = false;
}

fn aluRotateRight(self: *Cpu, value: u8, cy: u1) u8 {
    const result = @as(u8, cy) << 7 | value >> 1;

    self.regs.flags.c = value & 0x01 != 0;
    self.regs.flags.h = false;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;

    return result;
}

fn aluRotateLeft(self: *Cpu, value: u8, cy: u1) u8 {
    const result = value << 1 | cy;

    self.regs.flags.c = value & 0x80 != 0;
    self.regs.flags.h = false;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;

    return result;
}

fn rotateA(self: *Cpu, comptime op: RotateOp) void {
    const value = self.regs._8.a;
    const result = switch (op) {
        .rl => self.aluRotateLeft(value, @intFromBool(self.regs.flags.c)),
        .rlc => self.aluRotateLeft(value, @intCast(value >> 7)),
        .rr => self.aluRotateRight(value, @intFromBool(self.regs.flags.c)),
        .rrc => self.aluRotateRight(value, @intCast(value & 0x01)),
    };
    self.regs.flags.z = false;
    self.regs._8.a = result;
}

fn rotate(self: *Cpu, comptime target: Target, comptime op: RotateOp) void {
    const value = target.getValue(self);
    const result = switch (op) {
        .rl => self.aluRotateLeft(value, @intFromBool(self.regs.flags.c)),
        .rlc => self.aluRotateLeft(value, @intCast(value >> 7)),
        .rr => self.aluRotateRight(value, @intFromBool(self.regs.flags.c)),
        .rrc => self.aluRotateRight(value, @intCast(value & 0x01)),
    };
    target.setValue(self, result);
}

fn sla(self: *Cpu, comptime target: Target) void {
    const value = target.getValue(self);
    const result = value << 1;

    self.regs.flags.c = value & 0x80 != 0;
    self.regs.flags.h = false;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;

    target.setValue(self, result);
}

fn sra(self: *Cpu, comptime target: Target) void {
    const value = target.getValue(self);
    const hi = value & 0x80;
    const result = hi | value >> 1;

    self.regs.flags.c = value & 0x01 != 0;
    self.regs.flags.h = false;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;

    target.setValue(self, result);
}

fn srl(self: *Cpu, comptime target: Target) void {
    const value = target.getValue(self);
    const result = value >> 1;

    self.regs.flags.c = value & 0x01 != 0;
    self.regs.flags.h = false;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;

    target.setValue(self, result);
}

fn swap(self: *Cpu, comptime target: Target) void {
    const value = target.getValue(self);
    const result = value >> 4 | value << 4;

    self.regs.flags.c = false;
    self.regs.flags.h = false;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;

    target.setValue(self, result);
}

fn bit(self: *Cpu, comptime target: Target, comptime n: u3) void {
    const value = target.getValue(self);
    const result = value & (1 << n);

    self.regs.flags.h = true;
    self.regs.flags.n = false;
    self.regs.flags.z = result == 0;
}

fn set(self: *Cpu, comptime target: Target, comptime n: u3) void {
    const value = target.getValue(self);
    const result = value | 1 << n;
    target.setValue(self, result);
}

fn res(self: *Cpu, comptime target: Target, comptime n: u3) void {
    const value = target.getValue(self);
    const result = value & ~@as(u8, 1 << n);
    target.setValue(self, result);
}

fn execute(self: *Cpu, opcode: u8) void {
    switch (opcode) {
        0x00 => {}, // nop
        0x01 => self.ld16(.bc),
        0x02 => self.ld(.addr_bc, .a),
        0x03 => self.inc16(.bc),
        0x04 => self.inc(.b),
        0x05 => self.dec(.b),
        0x06 => self.ld(.b, .imm),
        0x07 => self.rotateA(.rlc),
        0x08 => self.ldAbsSp(),
        0x09 => self.addHl(.bc),
        0x0A => self.ld(.a, .addr_bc),
        0x0B => self.dec16(.bc),
        0x0C => self.inc(.c),
        0x0D => self.dec(.c),
        0x0E => self.ld(.c, .imm),
        0x0F => self.rotateA(.rrc),
        0x10 => @panic("stop"),
        0x11 => self.ld16(.de),
        0x12 => self.ld(.addr_de, .a),
        0x13 => self.inc16(.de),
        0x14 => self.inc(.d),
        0x15 => self.dec(.d),
        0x16 => self.ld(.d, .imm),
        0x17 => self.rotateA(.rl),
        0x18 => self.jr(.always),
        0x19 => self.addHl(.de),
        0x1A => self.ld(.a, .addr_de),
        0x1B => self.dec16(.de),
        0x1C => self.inc(.e),
        0x1D => self.dec(.e),
        0x1E => self.ld(.e, .imm),
        0x1F => self.rotateA(.rr),
        0x20 => self.jr(.nz),
        0x21 => self.ld16(.hl),
        0x22 => self.ld(.addr_hli, .a),
        0x23 => self.inc16(.hl),
        0x24 => self.inc(.h),
        0x25 => self.dec(.h),
        0x26 => self.ld(.h, .imm),
        0x27 => self.daa(),
        0x28 => self.jr(.z),
        0x29 => self.addHl(.hl),
        0x2A => self.ld(.a, .addr_hli),
        0x2B => self.dec16(.hl),
        0x2C => self.inc(.l),
        0x2D => self.dec(.l),
        0x2E => self.ld(.l, .imm),
        0x2F => self.cpl(),
        0x30 => self.jr(.nc),
        0x31 => self.ld16(.sp),
        0x32 => self.ld(.addr_hld, .a),
        0x33 => self.inc16(.sp),
        0x34 => self.inc(.addr_hl),
        0x35 => self.dec(.addr_hl),
        0x36 => self.ld(.addr_hl, .imm),
        0x37 => self.scf(),
        0x38 => self.jr(.c),
        0x39 => self.addHl(.sp),
        0x3A => self.ld(.a, .addr_hld),
        0x3B => self.dec16(.sp),
        0x3C => self.inc(.a),
        0x3D => self.dec(.a),
        0x3E => self.ld(.a, .imm),
        0x3F => self.ccf(),
        0x40 => self.ld(.b, .b),
        0x41 => self.ld(.b, .c),
        0x42 => self.ld(.b, .d),
        0x43 => self.ld(.b, .e),
        0x44 => self.ld(.b, .h),
        0x45 => self.ld(.b, .l),
        0x46 => self.ld(.b, .addr_hl),
        0x47 => self.ld(.b, .a),
        0x48 => self.ld(.c, .b),
        0x49 => self.ld(.c, .c),
        0x4A => self.ld(.c, .d),
        0x4B => self.ld(.c, .e),
        0x4C => self.ld(.c, .h),
        0x4D => self.ld(.c, .l),
        0x4E => self.ld(.c, .addr_hl),
        0x4F => self.ld(.c, .a),
        0x50 => self.ld(.d, .b),
        0x51 => self.ld(.d, .c),
        0x52 => self.ld(.d, .d),
        0x53 => self.ld(.d, .e),
        0x54 => self.ld(.d, .h),
        0x55 => self.ld(.d, .l),
        0x56 => self.ld(.d, .addr_hl),
        0x57 => self.ld(.d, .a),
        0x58 => self.ld(.e, .b),
        0x59 => self.ld(.e, .c),
        0x5A => self.ld(.e, .d),
        0x5B => self.ld(.e, .e),
        0x5C => self.ld(.e, .h),
        0x5D => self.ld(.e, .l),
        0x5E => self.ld(.e, .addr_hl),
        0x5F => self.ld(.e, .a),
        0x60 => self.ld(.h, .b),
        0x61 => self.ld(.h, .c),
        0x62 => self.ld(.h, .d),
        0x63 => self.ld(.h, .e),
        0x64 => self.ld(.h, .h),
        0x65 => self.ld(.h, .l),
        0x66 => self.ld(.h, .addr_hl),
        0x67 => self.ld(.h, .a),
        0x68 => self.ld(.l, .b),
        0x69 => self.ld(.l, .c),
        0x6A => self.ld(.l, .d),
        0x6B => self.ld(.l, .e),
        0x6C => self.ld(.l, .h),
        0x6D => self.ld(.l, .l),
        0x6E => self.ld(.l, .addr_hl),
        0x6F => self.ld(.l, .a),
        0x70 => self.ld(.addr_hl, .b),
        0x71 => self.ld(.addr_hl, .c),
        0x72 => self.ld(.addr_hl, .d),
        0x73 => self.ld(.addr_hl, .e),
        0x74 => self.ld(.addr_hl, .h),
        0x75 => self.ld(.addr_hl, .l),
        0x76 => self.halt(),
        0x77 => self.ld(.addr_hl, .a),
        0x78 => self.ld(.a, .b),
        0x79 => self.ld(.a, .c),
        0x7A => self.ld(.a, .d),
        0x7B => self.ld(.a, .e),
        0x7C => self.ld(.a, .h),
        0x7D => self.ld(.a, .l),
        0x7E => self.ld(.a, .addr_hl),
        0x7F => self.ld(.a, .a),
        0x80 => self.add(.b),
        0x81 => self.add(.c),
        0x82 => self.add(.d),
        0x83 => self.add(.e),
        0x84 => self.add(.h),
        0x85 => self.add(.l),
        0x86 => self.add(.addr_hl),
        0x87 => self.add(.a),
        0x88 => self.adc(.b),
        0x89 => self.adc(.c),
        0x8A => self.adc(.d),
        0x8B => self.adc(.e),
        0x8C => self.adc(.h),
        0x8D => self.adc(.l),
        0x8E => self.adc(.addr_hl),
        0x8F => self.adc(.a),
        0x90 => self.sub(.b),
        0x91 => self.sub(.c),
        0x92 => self.sub(.d),
        0x93 => self.sub(.e),
        0x94 => self.sub(.h),
        0x95 => self.sub(.l),
        0x96 => self.sub(.addr_hl),
        0x97 => self.sub(.a),
        0x98 => self.sbc(.b),
        0x99 => self.sbc(.c),
        0x9A => self.sbc(.d),
        0x9B => self.sbc(.e),
        0x9C => self.sbc(.h),
        0x9D => self.sbc(.l),
        0x9E => self.sbc(.addr_hl),
        0x9F => self.sbc(.a),
        0xA0 => self.bitAnd(.b),
        0xA1 => self.bitAnd(.c),
        0xA2 => self.bitAnd(.d),
        0xA3 => self.bitAnd(.e),
        0xA4 => self.bitAnd(.h),
        0xA5 => self.bitAnd(.l),
        0xA6 => self.bitAnd(.addr_hl),
        0xA7 => self.bitAnd(.a),
        0xA8 => self.bitXor(.b),
        0xA9 => self.bitXor(.c),
        0xAA => self.bitXor(.d),
        0xAB => self.bitXor(.e),
        0xAC => self.bitXor(.h),
        0xAD => self.bitXor(.l),
        0xAE => self.bitXor(.addr_hl),
        0xAF => self.bitXor(.a),
        0xB0 => self.bitOr(.b),
        0xB1 => self.bitOr(.c),
        0xB2 => self.bitOr(.d),
        0xB3 => self.bitOr(.e),
        0xB4 => self.bitOr(.h),
        0xB5 => self.bitOr(.l),
        0xB6 => self.bitOr(.addr_hl),
        0xB7 => self.bitOr(.a),
        0xB8 => self.cp(.b),
        0xB9 => self.cp(.c),
        0xBA => self.cp(.d),
        0xBB => self.cp(.e),
        0xBC => self.cp(.h),
        0xBD => self.cp(.l),
        0xBE => self.cp(.addr_hl),
        0xBF => self.cp(.a),
        0xC0 => self.ret(.nz),
        0xC1 => self.pop(.bc),
        0xC2 => self.jp(.nz),
        0xC3 => self.jp(.always),
        0xC4 => self.call(.nz),
        0xC5 => self.push(.bc),
        0xC6 => self.add(.imm),
        0xC7 => self.rst(0x00),
        0xC8 => self.ret(.z),
        0xC9 => self.ret(.always),
        0xCA => self.jp(.z),
        0xCB => self.prefixCb(),
        0xCC => self.call(.z),
        0xCD => self.call(.always),
        0xCE => self.adc(.imm),
        0xCF => self.rst(0x08),
        0xD0 => self.ret(.nc),
        0xD1 => self.pop(.de),
        0xD2 => self.jp(.nc),
        0xD4 => self.call(.nc),
        0xD5 => self.push(.de),
        0xD6 => self.sub(.imm),
        0xD7 => self.rst(0x10),
        0xD8 => self.ret(.c),
        0xD9 => self.reti(),
        0xDA => self.jp(.c),
        0xDC => self.call(.c),
        0xDE => self.sbc(.imm),
        0xDF => self.rst(0x18),
        0xE0 => self.ld(.zero_page, .a),
        0xE1 => self.pop(.hl),
        0xE2 => self.ld(.zero_page_c, .a),
        0xE5 => self.push(.hl),
        0xE6 => self.bitAnd(.imm),
        0xE7 => self.rst(0x20),
        0xE8 => self.addSpImm(),
        0xE9 => self.jpHl(),
        0xEA => self.ld(.absolute, .a),
        0xEE => self.bitXor(.imm),
        0xEF => self.rst(0x28),
        0xF0 => self.ld(.a, .zero_page),
        0xF1 => self.pop(.sp),
        0xF2 => self.ld(.a, .zero_page_c),
        0xF3 => self.di(),
        0xF5 => self.push(.sp),
        0xF6 => self.bitOr(.imm),
        0xF7 => self.rst(0x30),
        0xF8 => self.ldHlSpImm(),
        0xF9 => self.ldSpHl(),
        0xFA => self.ld(.a, .absolute),
        0xFB => self.ei(),
        0xFE => self.cp(.imm),
        0xFF => self.rst(0x38),
        0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD => @panic("illegal instruction"),
    }
}

fn prefixCb(self: *Cpu) void {
    const opcode = self.read8();
    switch (opcode) {
        0x00 => self.rotate(.b, .rlc),
        0x01 => self.rotate(.c, .rlc),
        0x02 => self.rotate(.d, .rlc),
        0x03 => self.rotate(.e, .rlc),
        0x04 => self.rotate(.h, .rlc),
        0x05 => self.rotate(.l, .rlc),
        0x06 => self.rotate(.addr_hl, .rlc),
        0x07 => self.rotate(.a, .rlc),
        0x08 => self.rotate(.b, .rrc),
        0x09 => self.rotate(.c, .rrc),
        0x0A => self.rotate(.d, .rrc),
        0x0B => self.rotate(.e, .rrc),
        0x0C => self.rotate(.h, .rrc),
        0x0D => self.rotate(.l, .rrc),
        0x0E => self.rotate(.addr_hl, .rrc),
        0x0F => self.rotate(.a, .rrc),
        0x10 => self.rotate(.b, .rl),
        0x11 => self.rotate(.c, .rl),
        0x12 => self.rotate(.d, .rl),
        0x13 => self.rotate(.e, .rl),
        0x14 => self.rotate(.h, .rl),
        0x15 => self.rotate(.l, .rl),
        0x16 => self.rotate(.addr_hl, .rl),
        0x17 => self.rotate(.a, .rl),
        0x18 => self.rotate(.b, .rr),
        0x19 => self.rotate(.c, .rr),
        0x1A => self.rotate(.d, .rr),
        0x1B => self.rotate(.e, .rr),
        0x1C => self.rotate(.h, .rr),
        0x1D => self.rotate(.l, .rr),
        0x1E => self.rotate(.addr_hl, .rr),
        0x1F => self.rotate(.a, .rr),
        0x20 => self.sla(.b),
        0x21 => self.sla(.c),
        0x22 => self.sla(.d),
        0x23 => self.sla(.e),
        0x24 => self.sla(.h),
        0x25 => self.sla(.l),
        0x26 => self.sla(.addr_hl),
        0x27 => self.sla(.a),
        0x28 => self.sra(.b),
        0x29 => self.sra(.c),
        0x2A => self.sra(.d),
        0x2B => self.sra(.e),
        0x2C => self.sra(.h),
        0x2D => self.sra(.l),
        0x2E => self.sra(.addr_hl),
        0x2F => self.sra(.a),
        0x30 => self.swap(.b),
        0x31 => self.swap(.c),
        0x32 => self.swap(.d),
        0x33 => self.swap(.e),
        0x34 => self.swap(.h),
        0x35 => self.swap(.l),
        0x36 => self.swap(.addr_hl),
        0x37 => self.swap(.a),
        0x38 => self.srl(.b),
        0x39 => self.srl(.c),
        0x3A => self.srl(.d),
        0x3B => self.srl(.e),
        0x3C => self.srl(.h),
        0x3D => self.srl(.l),
        0x3E => self.srl(.addr_hl),
        0x3F => self.srl(.a),
        0x40 => self.bit(.b, 0),
        0x41 => self.bit(.c, 0),
        0x42 => self.bit(.d, 0),
        0x43 => self.bit(.e, 0),
        0x44 => self.bit(.h, 0),
        0x45 => self.bit(.l, 0),
        0x46 => self.bit(.addr_hl, 0),
        0x47 => self.bit(.a, 0),
        0x48 => self.bit(.b, 1),
        0x49 => self.bit(.c, 1),
        0x4A => self.bit(.d, 1),
        0x4B => self.bit(.e, 1),
        0x4C => self.bit(.h, 1),
        0x4D => self.bit(.l, 1),
        0x4E => self.bit(.addr_hl, 1),
        0x4F => self.bit(.a, 1),
        0x50 => self.bit(.b, 2),
        0x51 => self.bit(.c, 2),
        0x52 => self.bit(.d, 2),
        0x53 => self.bit(.e, 2),
        0x54 => self.bit(.h, 2),
        0x55 => self.bit(.l, 2),
        0x56 => self.bit(.addr_hl, 2),
        0x57 => self.bit(.a, 2),
        0x58 => self.bit(.b, 3),
        0x59 => self.bit(.c, 3),
        0x5A => self.bit(.d, 3),
        0x5B => self.bit(.e, 3),
        0x5C => self.bit(.h, 3),
        0x5D => self.bit(.l, 3),
        0x5E => self.bit(.addr_hl, 3),
        0x5F => self.bit(.a, 3),
        0x60 => self.bit(.b, 4),
        0x61 => self.bit(.c, 4),
        0x62 => self.bit(.d, 4),
        0x63 => self.bit(.e, 4),
        0x64 => self.bit(.h, 4),
        0x65 => self.bit(.l, 4),
        0x66 => self.bit(.addr_hl, 4),
        0x67 => self.bit(.a, 4),
        0x68 => self.bit(.b, 5),
        0x69 => self.bit(.c, 5),
        0x6A => self.bit(.d, 5),
        0x6B => self.bit(.e, 5),
        0x6C => self.bit(.h, 5),
        0x6D => self.bit(.l, 5),
        0x6E => self.bit(.addr_hl, 5),
        0x6F => self.bit(.a, 5),
        0x70 => self.bit(.b, 6),
        0x71 => self.bit(.c, 6),
        0x72 => self.bit(.d, 6),
        0x73 => self.bit(.e, 6),
        0x74 => self.bit(.h, 6),
        0x75 => self.bit(.l, 6),
        0x76 => self.bit(.addr_hl, 6),
        0x77 => self.bit(.a, 6),
        0x78 => self.bit(.b, 7),
        0x79 => self.bit(.c, 7),
        0x7A => self.bit(.d, 7),
        0x7B => self.bit(.e, 7),
        0x7C => self.bit(.h, 7),
        0x7D => self.bit(.l, 7),
        0x7E => self.bit(.addr_hl, 7),
        0x7F => self.bit(.a, 7),
        0x80 => self.res(.b, 0),
        0x81 => self.res(.c, 0),
        0x82 => self.res(.d, 0),
        0x83 => self.res(.e, 0),
        0x84 => self.res(.h, 0),
        0x85 => self.res(.l, 0),
        0x86 => self.res(.addr_hl, 0),
        0x87 => self.res(.a, 0),
        0x88 => self.res(.b, 1),
        0x89 => self.res(.c, 1),
        0x8A => self.res(.d, 1),
        0x8B => self.res(.e, 1),
        0x8C => self.res(.h, 1),
        0x8D => self.res(.l, 1),
        0x8E => self.res(.addr_hl, 1),
        0x8F => self.res(.a, 1),
        0x90 => self.res(.b, 2),
        0x91 => self.res(.c, 2),
        0x92 => self.res(.d, 2),
        0x93 => self.res(.e, 2),
        0x94 => self.res(.h, 2),
        0x95 => self.res(.l, 2),
        0x96 => self.res(.addr_hl, 2),
        0x97 => self.res(.a, 2),
        0x98 => self.res(.b, 3),
        0x99 => self.res(.c, 3),
        0x9A => self.res(.d, 3),
        0x9B => self.res(.e, 3),
        0x9C => self.res(.h, 3),
        0x9D => self.res(.l, 3),
        0x9E => self.res(.addr_hl, 3),
        0x9F => self.res(.a, 3),
        0xA0 => self.res(.b, 4),
        0xA1 => self.res(.c, 4),
        0xA2 => self.res(.d, 4),
        0xA3 => self.res(.e, 4),
        0xA4 => self.res(.h, 4),
        0xA5 => self.res(.l, 4),
        0xA6 => self.res(.addr_hl, 4),
        0xA7 => self.res(.a, 4),
        0xA8 => self.res(.b, 5),
        0xA9 => self.res(.c, 5),
        0xAA => self.res(.d, 5),
        0xAB => self.res(.e, 5),
        0xAC => self.res(.h, 5),
        0xAD => self.res(.l, 5),
        0xAE => self.res(.addr_hl, 5),
        0xAF => self.res(.a, 5),
        0xB0 => self.res(.b, 6),
        0xB1 => self.res(.c, 6),
        0xB2 => self.res(.d, 6),
        0xB3 => self.res(.e, 6),
        0xB4 => self.res(.h, 6),
        0xB5 => self.res(.l, 6),
        0xB6 => self.res(.addr_hl, 6),
        0xB7 => self.res(.a, 6),
        0xB8 => self.res(.b, 7),
        0xB9 => self.res(.c, 7),
        0xBA => self.res(.d, 7),
        0xBB => self.res(.e, 7),
        0xBC => self.res(.h, 7),
        0xBD => self.res(.l, 7),
        0xBE => self.res(.addr_hl, 7),
        0xBF => self.res(.a, 7),
        0xC0 => self.set(.b, 0),
        0xC1 => self.set(.c, 0),
        0xC2 => self.set(.d, 0),
        0xC3 => self.set(.e, 0),
        0xC4 => self.set(.h, 0),
        0xC5 => self.set(.l, 0),
        0xC6 => self.set(.addr_hl, 0),
        0xC7 => self.set(.a, 0),
        0xC8 => self.set(.b, 1),
        0xC9 => self.set(.c, 1),
        0xCA => self.set(.d, 1),
        0xCB => self.set(.e, 1),
        0xCC => self.set(.h, 1),
        0xCD => self.set(.l, 1),
        0xCE => self.set(.addr_hl, 1),
        0xCF => self.set(.a, 1),
        0xD0 => self.set(.b, 2),
        0xD1 => self.set(.c, 2),
        0xD2 => self.set(.d, 2),
        0xD3 => self.set(.e, 2),
        0xD4 => self.set(.h, 2),
        0xD5 => self.set(.l, 2),
        0xD6 => self.set(.addr_hl, 2),
        0xD7 => self.set(.a, 2),
        0xD8 => self.set(.b, 3),
        0xD9 => self.set(.c, 3),
        0xDA => self.set(.d, 3),
        0xDB => self.set(.e, 3),
        0xDC => self.set(.h, 3),
        0xDD => self.set(.l, 3),
        0xDE => self.set(.addr_hl, 3),
        0xDF => self.set(.a, 3),
        0xE0 => self.set(.b, 4),
        0xE1 => self.set(.c, 4),
        0xE2 => self.set(.d, 4),
        0xE3 => self.set(.e, 4),
        0xE4 => self.set(.h, 4),
        0xE5 => self.set(.l, 4),
        0xE6 => self.set(.addr_hl, 4),
        0xE7 => self.set(.a, 4),
        0xE8 => self.set(.b, 5),
        0xE9 => self.set(.c, 5),
        0xEA => self.set(.d, 5),
        0xEB => self.set(.e, 5),
        0xEC => self.set(.h, 5),
        0xED => self.set(.l, 5),
        0xEE => self.set(.addr_hl, 5),
        0xEF => self.set(.a, 5),
        0xF0 => self.set(.b, 6),
        0xF1 => self.set(.c, 6),
        0xF2 => self.set(.d, 6),
        0xF3 => self.set(.e, 6),
        0xF4 => self.set(.h, 6),
        0xF5 => self.set(.l, 6),
        0xF6 => self.set(.addr_hl, 6),
        0xF7 => self.set(.a, 6),
        0xF8 => self.set(.b, 7),
        0xF9 => self.set(.c, 7),
        0xFA => self.set(.d, 7),
        0xFB => self.set(.e, 7),
        0xFC => self.set(.h, 7),
        0xFD => self.set(.l, 7),
        0xFE => self.set(.addr_hl, 7),
        0xFF => self.set(.a, 7),
    }
}

test {
    _ = @import("cpu/registers.zig");
}
