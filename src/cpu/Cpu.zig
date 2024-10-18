const std = @import("std");
const registers = @import("registers.zig");
const target = @import("target.zig");
const Bus = @import("../Bus.zig");

const Reg16 = registers.Reg16;

pub const Registers = registers.Registers;
pub const Flags = registers.Flags;
pub const Target = target.Target;

const Cpu = @This();

regs: Registers,
bus: Bus,

pub const init: Cpu = .{ .regs = .init, .bus = .init };

pub fn step(self: *Cpu) void {
    const opcode = self.read8();
    self.execute(opcode);
}

pub fn read8(self: *Cpu) u8 {
    const value = self.bus.read(self.regs._16.pc);
    self.regs._16.pc += 1;
    return value;
}

fn read16(self: *Cpu) u16 {
    const lo: u16 = self.read8();
    const hi: u16 = self.read8();
    return hi << 8 | lo;
}

fn ld(self: *Cpu, comptime dst: Target, comptime src: Target) void {
    const value = src.getValue(self);
    dst.setValue(self, value);
}

fn ld16(self: *Cpu, comptime dst: Target) void {
    const value = self.read16();
    dst.setValue16(self, value);
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

fn execute(self: *Cpu, opcode: u8) void {
    switch (opcode) {
        0x01 => self.ld16(.bc),
        0x09 => self.addHl(.bc),
        0x11 => self.ld16(.de),
        0x19 => self.addHl(.de),
        0x21 => self.ld16(.hl),
        0x29 => self.addHl(.hl),
        0x31 => self.ld16(.sp),
        0x39 => self.addHl(.sp),
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
        0x76 => {},
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
        0xC6 => self.add(.imm),
        0xCE => self.adc(.imm),
        0xD6 => self.sub(.imm),
        0xDE => self.sbc(.imm),
        0xE6 => self.bitAnd(.imm),
        0xEE => self.bitXor(.imm),
        0xF6 => self.bitOr(.imm),
        0xFE => self.cp(.imm),

        else => {},
    }
}

test {
    _ = @import("registers.zig");
}
