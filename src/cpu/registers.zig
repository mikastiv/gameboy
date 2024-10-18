const std = @import("std");

pub const Flags = packed struct(u8) {
    _unused: u4,
    c: bool,
    h: bool,
    n: bool,
    z: bool,
};

pub const Registers = extern union {
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
