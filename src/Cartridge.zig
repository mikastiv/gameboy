const Cartridge = @This();

const std = @import("std");
const builtin = @import("builtin");

pub const Header = @import("cartridge/Header.zig");
pub const Type = Header.CartridgeType;

const Mapper = union(enum) {
    rom_only,
    mbc1: Mbc1,
    mbc2: Mbc2,
    mbc3: Mbc3,
    mbc5: Mbc5,
};

const Mbc1 = struct {
    ram_enabled: bool,
    rom_bank1_select: u5,
    rom_bank2_select: u2,
    mode: bool,
    multicart: bool,

    fn romOffsets(self: Mbc1) struct { usize, usize } {
        const shift: u3 = if (self.multicart) 4 else 5;
        const mask: u8 = if (self.multicart) 0xF else 0xFF;
        const lo = self.rom_bank1_select & mask;
        const hi = @as(u8, self.rom_bank2_select) << shift;

        const low_bank: usize = if (self.mode) hi else 0;
        const high_bank: usize = hi | lo;

        return .{ low_bank * rom_bank_size, high_bank * rom_bank_size };
    }

    fn ramOffset(self: Mbc1) usize {
        const bank: usize = if (self.mode) self.rom_bank2_select else 0;
        return bank * ram_bank_size;
    }
};

const Mbc2 = struct {
    ram_enabled: bool,
    rom_select: u4,
};

const Mbc3 = struct {
    ram_enabled: bool,
    rom_select: u8,
    ram_select: u3,
    mbc30: bool,
};

const Mbc5 = struct {
    ram_enabled: bool,
    rom_bank1_select: u8,
    rom_bank2_select: u1,
    ram_select: u4,

    fn romOffset(self: Mbc5) usize {
        const lo: usize = self.rom_bank1_select;
        const hi: usize = @as(u16, self.rom_bank2_select) << 8;

        const high_bank = hi | lo;

        return high_bank * rom_bank_size;
    }
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
                .multicart = rom.len >= 0x44000 and std.mem.eql(u8, rom[0x104..0x134], rom[0x40104..0x40134]),
            },
        },
        .mbc2,
        .mbc2_battery,
        => .{
            .mbc2 = .{
                .ram_enabled = false,
                .rom_select = 1,
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
                .rom_select = 1,
                .ram_select = 0,
                .mbc30 = rom.len >= 0x200000 or header.ram_size > 0x8000,
            },
        },
        .mbc5,
        .mbc5_ram,
        .mbc5_ram_battery,
        .mbc5_rumble,
        .mbc5_rumble_ram,
        .mbc5_rumble_ram_battery,
        => .{
            .mbc5 = .{
                .ram_enabled = false,
                .rom_bank1_select = 1,
                .rom_bank2_select = 0,
                .ram_select = 0,
            },
        },
        else => unreachable,
    };

    const ram: ?[]u8 = if (header.ram_size > 0 or mapper == .mbc2)
        try std.heap.page_allocator.alloc(u8, if (mapper == .mbc2) 512 else header.ram_size)
    else
        null;

    if (ram) |r| {
        loadRam(&header, r) catch {
            std.log.debug("no save file found", .{});
        };
    }

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
        .mbc2 => |*mbc| switch (addr >> 8) {
            0x00...0x3F => {
                const bit8 = addr & 0x100 != 0;
                if (bit8) {
                    mbc.rom_select = @intCast(value & 0xF);
                    if (mbc.rom_select == 0) mbc.rom_select = 1;
                } else {
                    mbc.ram_enabled = (value & 0xF) == 0xA;
                }

                const hi: usize = mbc.rom_select;
                self.rom_bank_hi_offset = hi * rom_bank_size;
            },
            0x40...0x7F => {},
            else => unreachable,
        },
        .mbc3 => |*mbc| switch (addr >> 8) {
            0x00...0x1F => mbc.ram_enabled = (value & 0xF) == 0xA,
            0x20...0x3F => {
                mbc.rom_select = if (value == 0) 1 else value;

                const hi: usize = mbc.rom_select;
                self.rom_bank_hi_offset = hi * rom_bank_size;
            },
            0x40...0x5F => {
                const mask: u8 = if (mbc.mbc30) 0x7 else 0x3;
                mbc.ram_select = @intCast(value & mask);

                const ram_bank: usize = mbc.ram_select;
                self.ram_bank_offset = ram_bank * ram_bank_size;
            },
            0x60...0x7F => {},
            else => unreachable,
        },
        .mbc5 => |*mbc| switch (addr >> 8) {
            0x00...0x1F => mbc.ram_enabled = (value & 0xF) == 0xA,
            0x20...0x2F => {
                mbc.rom_bank1_select = value;
                self.rom_bank_hi_offset = mbc.romOffset();
            },
            0x30...0x3F => {
                mbc.rom_bank2_select = @intCast(value & 1);
                self.rom_bank_hi_offset = mbc.romOffset();
            },
            0x40...0x5F => {
                mbc.ram_select = @intCast(value & 0xF);

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
        .mbc2 => |mbc| if (mbc.ram_enabled) self.readRamBank(addr) & 0xF else 0xFF,
        .mbc3 => |mbc| if (mbc.ram_enabled) blk: {
            if (!mbc.mbc30 and mbc.ram_select >= 0x4) {
                break :blk 0xFF;
            }

            break :blk self.readRamBank(addr);
        } else 0xFF,
        .mbc5 => |mbc| if (mbc.ram_enabled) self.readRamBank(addr) else 0xFF,
    } else 0xFF;
}

pub fn ramWrite(self: *Cartridge, addr: u16, value: u8) void {
    if (self.ram) |_| switch (self.mapper) {
        .rom_only => self.writeRamBank(addr, value),
        .mbc1 => |mbc| if (mbc.ram_enabled) {
            self.writeRamBank(addr, value);
        },
        .mbc2 => |mbc| if (mbc.ram_enabled) {
            self.writeRamBank(addr, value);
        },
        .mbc3 => |mbc| if (mbc.ram_enabled) blk: {
            if (!mbc.mbc30 and mbc.ram_select >= 0x4) {
                break :blk;
            }

            self.writeRamBank(addr, value);
        } else {},
        .mbc5 => |mbc| if (mbc.ram_enabled) {
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

fn saveFilename(rom_title: []const u8, buffer: []u8) ![]u8 {
    const filename = try std.fmt.bufPrint(buffer, "{s}.gbs", .{rom_title});

    for (filename) |*char| {
        char.* = std.ascii.toLower(char.*);
    }

    std.mem.replaceScalar(u8, filename, ' ', '_');

    return filename;
}

fn loadRam(header: *const Header, ram: []u8) !void {
    if (!header.cartridge_type.hasBattery()) return;

    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const filename = try saveFilename(header.title, &buffer);

    const save_file = try std.fs.cwd().openFile(filename, .{});
    defer save_file.close();

    const size = try save_file.readAll(ram);
    std.debug.assert(size == ram.len);
}

pub fn saveRam(self: *const Cartridge) !void {
    if (!self.header.cartridge_type.hasBattery()) return;

    if (self.ram) |ram| {
        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        const filename = try saveFilename(self.header.title, &buffer);

        const save_file = try std.fs.cwd().createFile(filename, .{});
        defer save_file.close();

        try save_file.writeAll(ram);
    }
}
