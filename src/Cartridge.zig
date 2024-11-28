const Cartridge = @This();

const std = @import("std");
const builtin = @import("builtin");

pub const Header = @import("cartridge/Header.zig");
pub const Type = Header.CartridgeType;

const Mapper = union(enum) {
    rom_only,
    mbc1: struct {},
    mbc2: struct {},
    mbc3: struct {},
};

const bank_size = 0x4000;
const bank_mask = bank_size - 1;

const ram_bank_size = 0x2000;
const ram_bank_mask = ram_bank_size - 1;

rom: []const u8,
ram: ?[]u8,
mapper: Mapper,
bank_lo: []const u8,
bank_hi: []const u8,
ram_bank: ?[]u8,

pub fn init(rom: []const u8) !Cartridge {
    const header = Header.init(rom);

    if (builtin.mode == .Debug) {
        const stderr = std.io.getStdErr().writer();
        header.write(stderr) catch unreachable;
    }

    const ram: ?[]u8 = if (header.cartridge_type.hasRam())
        try std.heap.page_allocator.alloc(u8, header.ram_size)
    else
        null;

    const ram_bank: ?[]u8 = if (ram) |r|
        r[0..ram_bank_size]
    else
        null;

    return switch (header.cartridge_type) {
        .rom_only,
        .rom_ram_1,
        .rom_ram_battery_1,
        => .{
            .rom = rom,
            .ram = ram,
            .mapper = .rom_only,
            .bank_lo = rom[0..bank_size],
            .bank_hi = rom[bank_size..],
            .ram_bank = ram_bank,
        },
        .mbc1,
        .mbc1_ram,
        .mbc1_ram_battery,
        => .{
            .rom = rom,
            .ram = ram,
            .mapper = .rom_only,
            .bank_lo = rom[0..bank_size],
            .bank_hi = rom[bank_size .. bank_size * 2],
            .ram_bank = ram_bank,
        },
        else => unreachable,
    };
}

pub fn read(self: *const Cartridge, addr: u16) u8 {
    return switch (addr) {
        0x0000...0x3FFF => self.bank_lo[addr],
        0x4000...0x7FFF => self.bank_hi[addr & bank_mask],
        else => unreachable,
    };
}

pub fn write(self: *Cartridge, addr: u16, value: u8) void {
    _ = addr; // autofix
    _ = value; // autofix
    switch (self.mapper) {
        .rom_only => {},
        else => unreachable,
    }
}

pub fn ramRead(self: *const Cartridge, addr: u16) u8 {
    return if (self.ram_bank) |ram|
        ram[addr & ram_bank_mask]
    else
        0xFF;
}

pub fn ramWrite(self: *Cartridge, addr: u16, value: u8) void {
    if (self.ram_bank) |ram| {
        ram[addr & ram_bank_mask] = value;
    }
}
