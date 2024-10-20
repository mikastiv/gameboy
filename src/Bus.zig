const std = @import("std");
const Rom = @import("Rom.zig");

const Bus = @This();

const wram_size = 0x2000;
const wram_mask = wram_size - 1;
const WRam = [wram_size]u8;

const hram_size = 0x80;
const hram_mask = hram_size - 1;
const HRam = [hram_size]u8;

rom: Rom,
wram: WRam,
hram: HRam,

pub fn init(rom: []const u8) Bus {
    return .{
        .rom = Rom.init(rom),
        .wram = std.mem.zeroes(WRam),
        .hram = std.mem.zeroes(HRam),
    };
}

pub fn peek(self: *Bus, address: u16) u8 {
    _ = self; // autofix
    _ = address; // autofix
    return 0;
}

pub fn read(self: *Bus, address: u16) u8 {
    _ = address; // autofix
    self.tick();
    return 0;
}

pub fn write(self: *Bus, address: u16, value: u8) void {
    self.tick();
    _ = address; // autofix
    _ = value; // autofix
}

pub fn tick(self: *Bus) void {
    _ = self; // autofix
}
