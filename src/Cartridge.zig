const Cartridge = @This();

const std = @import("std");
const builtin = @import("builtin");

pub const Header = @import("cartridge/Header.zig");
pub const Type = Header.CartridgeType;

const Mapper = union(enum) {
    rom_only,
    mbc1: Mbc1,
    mbc3: Mbc3,
};

// TODO: multicart
const Mbc1 = struct {
    ram_enabled: bool,
    rom_bank1_select: u5,
    rom_bank2_select: u2,
    mode: bool,

    fn romOffsets(self: Mbc1) struct { usize, usize } {
        const lo = self.rom_bank1_select;
        const hi = @as(u8, self.rom_bank2_select) << 5;

        const low_bank: usize = if (self.mode) @as(u8, self.rom_bank2_select) << 5 else 0;
        const high_bank: usize = hi | lo;

        return .{ low_bank * rom_bank_size, high_bank * rom_bank_size };
    }

    fn ramOffset(self: Mbc1) usize {
        const bank: usize = if (self.mode) self.rom_bank2_select else 0;
        return bank * ram_bank_size;
    }
};

const Mbc3 = struct {
    ram_enabled: bool,
    bank_select: u8,
    ram_select: u8,
};

const rom_bank_size = 0x4000;
const rom_bank_mask = rom_bank_size - 1;

const ram_bank_size = 0x2000;
const ram_bank_mask = ram_bank_size - 1;

header: Header,
rom: []const u8,
ram: ?[]u8,
mapper: Mapper,
rom_bank_lo_offset: usize,
rom_bank_hi_offset: usize,
ram_bank_offset: usize,

pub fn init(rom: []const u8) !Cartridge {
    const header = Header.init(rom);

    if (builtin.mode == .Debug) {
        const stderr = std.io.getStdErr().writer();
        header.write(stderr) catch unreachable;
    }

    const ram: ?[]u8 = if (header.ram_size > 0)
        try std.heap.page_allocator.alloc(u8, header.ram_size)
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
                .rom_bank1_select = 1,
                .rom_bank2_select = 0,
                .mode = false,
            },
        },
        .mbc3_timer_battery,
        .mbc3_timer_ram_battery_2,
        .mbc3,
        .mbc3_ram_2,
        .mbc3_ram_battery_2,
        => .{
            .mbc3 = .{
                .ram_enabled = false,
                .bank_select = 1,
                .ram_select = 0,
            },
        },
        else => unreachable,
    };

    return .{
        .header = header,
        .rom = rom,
        .ram = ram,
        .mapper = mapper,
        .rom_bank_lo_offset = 0,
        .rom_bank_hi_offset = rom_bank_size,
        .ram_bank_offset = 0,
    };
}

pub fn read(self: *const Cartridge, addr: u16) u8 {
    return switch (addr) {
        0x0000...0x3FFF => self.readRomBank(addr, self.rom_bank_lo_offset),
        0x4000...0x7FFF => self.readRomBank(addr, self.rom_bank_hi_offset),
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

                mbc.rom_bank1_select = @intCast(select);

                self.rom_bank_lo_offset, self.rom_bank_hi_offset = mbc.romOffsets();
            },
            0x40...0x5F => {
                mbc.rom_bank2_select = @intCast(value & 0x3);

                self.rom_bank_lo_offset, self.rom_bank_hi_offset = mbc.romOffsets();
                self.ram_bank_offset = mbc.ramOffset();
            },
            0x60...0x7F => {
                mbc.mode = (value & 1) != 0;

                self.rom_bank_lo_offset, self.rom_bank_hi_offset = mbc.romOffsets();
                self.ram_bank_offset = mbc.ramOffset();
            },
            else => unreachable,
        },
        .mbc3 => |*mbc| switch (addr >> 8) {
            0x00...0x1F => mbc.ram_enabled = (value & 0xF) == 0xA,
            0x20...0x3F => {
                mbc.bank_select = if (value == 0) 1 else value;

                const hi: usize = mbc.bank_select;
                self.rom_bank_hi_offset = hi * rom_bank_size;
            },
            0x40...0x5F => {
                mbc.ram_select = value & 0x3;

                const ram_bank: usize = mbc.ram_select;
                self.ram_bank_offset = ram_bank * ram_bank_size;
            },
            0x60...0x7F => {},
            else => unreachable,
        },
    }
}

pub fn ramRead(self: *const Cartridge, addr: u16) u8 {
    return if (self.ram) |_| switch (self.mapper) {
        .rom_only => self.readRamBank(addr),
        .mbc1 => |mbc| if (mbc.ram_enabled) self.readRamBank(addr) else 0xFF,
        .mbc3 => |mbc| if (mbc.ram_enabled) self.readRamBank(addr) else 0xFF,
    } else 0xFF;
}

pub fn ramWrite(self: *Cartridge, addr: u16, value: u8) void {
    if (self.ram) |_| switch (self.mapper) {
        .rom_only => self.writeRamBank(addr, value),
        .mbc1 => |mbc| if (mbc.ram_enabled) {
            self.writeRamBank(addr, value);
        },
        .mbc3 => |mbc| if (mbc.ram_enabled) {
            self.writeRamBank(addr, value);
        },
    };
}

fn readRomBank(self: *const Cartridge, addr: u16, offset: usize) u8 {
    const bank_addr = offset | (addr & rom_bank_mask);
    return self.rom[bank_addr & (self.rom.len - 1)];
}

fn readRamBank(self: *const Cartridge, addr: u16) u8 {
    const bank_addr = self.ram_bank_offset | (addr & ram_bank_mask);
    return self.ram.?[bank_addr & (self.ram.?.len - 1)];
}

fn writeRamBank(self: *Cartridge, addr: u16, value: u8) void {
    const bank_addr = self.ram_bank_offset | (addr & ram_bank_mask);
    self.ram.?[bank_addr & (self.ram.?.len - 1)] = value;
}
