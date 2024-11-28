const Cartridge = @This();

const std = @import("std");
const builtin = @import("builtin");

pub const Header = @import("cartridge/Header.zig");
pub const Type = Header.CartridgeType;

const Mapper = union(enum) {
    rom_only,
    mbc1: Mbc1,
};

// TODO: multicart
const Mbc1 = struct {
    ram_enabled: bool,
    bank1_select: u5,
    bank2_select: u2,
    mode: bool,

    fn romOffsets(self: Mbc1) struct { usize, usize } {
        const lo = self.bank1_select;
        const hi = @as(u8, self.bank2_select) << 5;

        const low_bank: usize = if (self.mode) self.bank2_select else 0;
        const high_bank: usize = hi | lo;

        return .{ low_bank * bank_size, high_bank * bank_size };
    }

    fn ramOffset(self: Mbc1) usize {
        const bank: usize = if (self.mode) self.bank2_select else 0;
        return bank * ram_bank_size;
    }
};

const bank_size = 0x4000;
const bank_mask = bank_size - 1;

const ram_bank_size = 0x2000;
const ram_bank_mask = ram_bank_size - 1;

header: Header,
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

    const mapper: Mapper = switch (header.cartridge_type) {
        .rom_only,
        .rom_ram_1,
        .rom_ram_battery_1,
        => .rom_only,
        .mbc1,
        .mbc1_ram,
        .mbc1_ram_battery,
        => .{
            .mbc1 = .{
                .ram_enabled = false,
                .bank1_select = 1,
                .bank2_select = 0,
                .mode = false,
            },
        },
        else => unreachable,
    };

    return .{
        .header = header,
        .rom = rom,
        .ram = ram,
        .mapper = mapper,
        .bank_lo = rom[0..bank_size],
        .bank_hi = rom[bank_size .. bank_size * 2],
        .ram_bank = ram_bank,
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
    switch (self.mapper) {
        .rom_only => {},
        .mbc1 => |*mbc| switch (addr >> 8) {
            0x00...0x1F => mbc.ram_enabled = (value & 0xF) == 0xA,
            0x20...0x3F => {
                var select = value & 0x1F;
                if (select == 0) select = 1;

                mbc.bank1_select = @intCast(select);

                const lo, const hi = mbc.romOffsets();
                const ram_offset = mbc.ramOffset();
                self.updateMappings(lo, hi, ram_offset);
            },
            0x40...0x5F => {
                mbc.bank2_select = @intCast(value & 0x3);

                const lo, const hi = mbc.romOffsets();
                const ram_offset = mbc.ramOffset();
                self.updateMappings(lo, hi, ram_offset);
            },
            0x60...0x7F => {
                mbc.mode = (value & 1) != 0;

                const lo, const hi = mbc.romOffsets();
                const ram_offset = mbc.ramOffset();
                self.updateMappings(lo, hi, ram_offset);
            },
            else => unreachable,
        },
    }
}

pub fn ramRead(self: *const Cartridge, addr: u16) u8 {
    return if (self.ram_bank) |bank| switch (self.mapper) {
        .rom_only => bank[addr & ram_bank_mask],
        .mbc1 => |mbc| if (mbc.ram_enabled) bank[addr & ram_bank_mask] else 0xFF,
    } else 0xFF;
}

pub fn ramWrite(self: *Cartridge, addr: u16, value: u8) void {
    if (self.ram_bank) |bank| switch (self.mapper) {
        .rom_only => bank[addr & ram_bank_mask] = value,
        .mbc1 => |mbc| if (mbc.ram_enabled) {
            bank[addr & ram_bank_mask] = value;
        },
    };
}

fn updateMappings(self: *Cartridge, bank_lo: usize, bank_hi: usize, ram_offset: usize) void {
    self.bank_lo = self.rom[bank_lo .. bank_lo + bank_size];
    self.bank_hi = self.rom[bank_hi .. bank_hi + bank_size];
    if (self.ram) |r| {
        self.ram_bank = r[ram_offset..ram_bank_size];
    }
}
