const Cpu = @import("../Cpu.zig");

pub const Target = enum(u16) {
    b = 0,
    c = 1,
    d = 2,
    e = 3,
    h = 4,
    l = 5,
    addr_hl = 6,
    a = 7,
    f,
    af,
    bc,
    de,
    hl,
    sp,
    addr_bc,
    addr_de,
    addr_hli,
    addr_hld,
    imm,
    absolute,
    zero_page,
    zero_page_c,

    fn getAddress(target: Target, cpu: *Cpu) u16 {
        return switch (target) {
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
            else => unreachable,
        };
    }

    pub fn getValue(target: Target, cpu: *Cpu) u8 {
        return switch (target) {
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
                const addr = target.getAddress(cpu);
                break :value cpu.bus.read(addr);
            },
        };
    }

    pub fn setValue(target: Target, cpu: *Cpu, data: u8) void {
        switch (target) {
            .a => cpu.regs._8.a = data,
            .b => cpu.regs._8.b = data,
            .c => cpu.regs._8.c = data,
            .d => cpu.regs._8.d = data,
            .e => cpu.regs._8.e = data,
            .h => cpu.regs._8.h = data,
            .l => cpu.regs._8.l = data,
            else => {
                const addr = target.getAddress(cpu);
                cpu.bus.write(addr, data);
            },
        }
    }

    pub fn getValue16(comptime target: Target, cpu: *Cpu) u16 {
        return switch (target) {
            .af => cpu.regs._16.af,
            .bc => cpu.regs._16.bc,
            .de => cpu.regs._16.de,
            .hl => cpu.regs._16.hl,
            .sp => cpu.regs._16.sp,
            else => @compileError("incompatible target " ++ @tagName(target)),
        };
    }

    pub fn setValue16(comptime target: Target, cpu: *Cpu, data: u16) void {
        switch (target) {
            .af => cpu.regs._16.af = data,
            .bc => cpu.regs._16.bc = data,
            .de => cpu.regs._16.de = data,
            .hl => cpu.regs._16.hl = data,
            .sp => cpu.regs._16.sp = data,
            else => @compileError("incompatible target " ++ @tagName(target)),
        }
    }
};
