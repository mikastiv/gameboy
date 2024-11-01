const Cpu = @import("../Cpu.zig");

pub const Target = enum {
    a,
    f,
    b,
    c,
    d,
    e,
    h,
    l,
    af,
    bc,
    de,
    hl,
    sp,
    imm,
    addr_hl,
    addr_bc,
    addr_de,
    addr_hli,
    addr_hld,
    absolute,
    zero_page,
    zero_page_c,

    fn getAddress(comptime target: Target, cpu: *Cpu) u16 {
        return switch (target) {
            .addr_bc => cpu.regs._16.bc,
            .addr_de => cpu.regs._16.de,
            .addr_hl => cpu.regs._16.hl,
            .addr_hli => blk: {
                defer cpu.regs._16.hl +%= 1;
                break :blk cpu.regs._16.hl;
            },
            .addr_hld => blk: {
                defer cpu.regs._16.hl -%= 1;
                break :blk cpu.regs._16.hl;
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
            else => @compileError("incompatible address target " ++ @tagName(target)),
        };
    }

    pub fn getValue(comptime target: Target, cpu: *Cpu) u8 {
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

    pub fn setValue(comptime target: Target, cpu: *Cpu, value: u8) void {
        switch (target) {
            .a => cpu.regs._8.a = value,
            .b => cpu.regs._8.b = value,
            .c => cpu.regs._8.c = value,
            .d => cpu.regs._8.d = value,
            .e => cpu.regs._8.e = value,
            .h => cpu.regs._8.h = value,
            .l => cpu.regs._8.l = value,
            else => {
                const addr = target.getAddress(cpu);
                cpu.bus.write(addr, value);
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

    pub fn setValue16(comptime target: Target, cpu: *Cpu, value: u16) void {
        switch (target) {
            .af => cpu.regs._16.af = value,
            .bc => cpu.regs._16.bc = value,
            .de => cpu.regs._16.de = value,
            .hl => cpu.regs._16.hl = value,
            .sp => cpu.regs._16.sp = value,
            else => @compileError("incompatible target " ++ @tagName(target)),
        }
    }
};

pub const CbTarget = enum(u3) {
    b = 0,
    c = 1,
    d = 2,
    e = 3,
    h = 4,
    l = 5,
    addr_hl = 6,
    a = 7,

    pub fn getValue(target: CbTarget, cpu: *Cpu) u8 {
        return switch (target) {
            .b => cpu.regs._8.b,
            .c => cpu.regs._8.c,
            .d => cpu.regs._8.d,
            .e => cpu.regs._8.e,
            .h => cpu.regs._8.h,
            .l => cpu.regs._8.l,
            .addr_hl => cpu.bus.read(cpu.regs._16.hl),
            .a => cpu.regs._8.a,
        };
    }

    pub fn setValue(target: CbTarget, cpu: *Cpu, value: u8) void {
        switch (target) {
            .b => cpu.regs._8.b = value,
            .c => cpu.regs._8.c = value,
            .d => cpu.regs._8.d = value,
            .e => cpu.regs._8.e = value,
            .h => cpu.regs._8.h = value,
            .l => cpu.regs._8.l = value,
            .addr_hl => cpu.bus.write(cpu.regs._16.hl, value),
            .a => cpu.regs._8.a = value,
        }
    }
};
