const std = @import("std");

const Registers = extern union {
    _16: extern struct {
        af: u16,
        bc: u16,
        de: u16,
        hl: u16,
    },
    _8: extern struct {
        flags: u8,
        a: u8,
        c: u8,
        d: u8,
        e: u8,
        l: u8,
        h: u8,
    },

    fn init() Registers {
        return .{
            ._16 = .{
                .af = 0,
                .bc = 0,
                .de = 0,
                .hl = 0,
            },
        };
    }
};

const expect = std.testing.expect;

test "registers" {
    var regs = Registers.init();

    regs._16.af = 0x1234;

    try expect(regs._8.a == 0x12);
    try expect(regs._8.flags == 0x34);
}
