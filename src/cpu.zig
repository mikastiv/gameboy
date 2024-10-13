const std = @import("std");

const Cpu = @This();

const Flags = packed struct(u8) {
    _unused: u4,
    c: bool,
    h: bool,
    n: bool,
    z: bool,
};

const Registers = extern union {
    flags: Flags,
    _16: extern struct {
        af: u16,
        bc: u16,
        de: u16,
        hl: u16,
        sp: u16,
        pc: u16,
    },
    _8: extern struct {
        f: u8,
        a: u8,
        c: u8,
        b: u8,
        e: u8,
        d: u8,
        l: u8,
        h: u8,
    },

    pub const init: Registers = .{
        ._16 = .{
            .af = 0,
            .bc = 0,
            .de = 0,
            .hl = 0,
            .sp = 0,
            .pc = 0,
        },
    };
};

const Bus = struct {
    const init: Bus = .{};

    fn read(self: *Bus, address: u16) u8 {
        _ = address; // autofix
        _ = self; // autofix
        return 0;
    }

    fn write(self: *Bus, address: u16, value: u8) void {
        _ = self; // autofix
        _ = address; // autofix
        _ = value; // autofix
    }

    fn tick(self: *Bus) void {
        _ = self; // autofix
    }
};

const Location = enum {
    a,
    f,
    b,
    c,
    d,
    e,
    h,
    l,
    addr_bc,
    addr_de,
    addr_hl,
    addr_hli,
    addr_hld,
    imm,
    absolute,
    zero_page,
    zero_page_c,

    fn getAddress(comptime loc: Location, cpu: *Cpu) u16 {
        return switch (loc) {
            .addr_bc => cpu.regs._16.bc,
            .addr_de => cpu.regs._16.de,
            .addr_hl => cpu.regs._16.hl,
            .addr_hli => blk: {
                const addr = cpu.regs._16.hl;
                cpu.regs._16.hl = addr +% 1;
                break :blk addr;
            },
            .addr_hld => blk: {
                const addr = cpu.regs._16.hl;
                cpu.regs._16.hl = addr -% 1;
                break :blk addr;
            },
            .absolute => cpu.read16(),
            .zero_page => blk: {
                const lo: u16 = cpu.read8();
                const addr = 0xFF00 | lo;
                break :blk addr;
            },
            .zero_page_c => blk: {
                const lo: u16 = cpu.regs._8.c;
                const addr = 0xFF00 | lo;
                break :blk addr;
            },
            else => @compileError("incompatible address loc " ++ @tagName(loc)),
        };
    }

    fn getValue(comptime loc: Location, cpu: *Cpu) u8 {
        return switch (loc) {
            .a => cpu.regs._8.a,
            .f => cpu.regs._8.f,
            .b => cpu.regs._8.b,
            .c => cpu.regs._8.c,
            .d => cpu.regs._8.d,
            .e => cpu.regs._8.e,
            .h => cpu.regs._8.h,
            .l => cpu.regs._8.l,
            .imm => cpu.read8(),
            else => value: {
                const addr = loc.getAddress();
                break :value cpu.bus.read(addr);
            },
        };
    }

    pub fn setValue(comptime loc: Location, cpu: *Cpu, data: u8) void {
        switch (loc) {
            .a => cpu.regs._8.a = data,
            .b => cpu.regs._8.b = data,
            .c => cpu.regs._8.c = data,
            .d => cpu.regs._8.d = data,
            .e => cpu.regs._8.e = data,
            .h => cpu.regs._8.h = data,
            .l => cpu.regs._8.l = data,
            else => {
                const addr = loc.getAddress();
                cpu.bus.write(addr, data);
            },
        }
    }
};

regs: Registers,
bus: Bus,

pub const init: Cpu = .{ .regs = .init, .bus = .init };

pub fn step(self: *Cpu) void {
    const opcode = self.read8();
    self.execute(opcode);
}

fn execute(self: *Cpu, opcode: u8) void {
    switch (opcode) {
        0x40 => self.ld(.b, .b),
        0x41 => self.ld(.b, .c),
        0x42 => self.ld(.b, .d),
        0x43 => self.ld(.b, .e),
        0x44 => self.ld(.b, .h),
        0x45 => self.ld(.b, .l),
        0x51 => self.ld(.d, .c),

        else => {},
    }
}

fn read8(self: *Cpu) u8 {
    const value = self.bus.read(self.regs._16.pc);
    self.regs._16.pc += 1;
    return value;
}

fn ld(self: *Cpu, comptime dst: Location, comptime src: Location) void {
    const value = src.getValue(self);
    dst.setValue(self, value);
}

const expect = std.testing.expect;

test "registers" {
    var regs: Registers = .init;

    regs._16.af = 0xBEEF;

    try expect(regs._8.a == 0xBE);
    try expect(regs._8.f == 0xEF);

    regs._8.b = 0x7A;
    regs._8.c = 0xFF;

    try expect(regs._16.bc == 0x7AFF);
}

test "flags" {
    var regs = std.mem.zeroes(Registers);

    regs._8.f = 0;
    regs.flags.z = true;
    try expect(regs._8.f == 0x80);
    regs.flags.c = true;
    try expect(regs._8.f == 0x90);
    regs.flags.n = true;
    try expect(regs._8.f == 0xD0);
}
