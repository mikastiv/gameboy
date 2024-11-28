const Cartridge = @This();

const std = @import("std");
const builtin = @import("builtin");

pub const Header = @import("cartridge/Header.zig");

data: []const u8,

pub fn init(rom: []const u8) Cartridge {
    const header = Header.init(rom);

    if (builtin.mode == .Debug) {
        const stderr = std.io.getStdErr().writer();
        header.write(stderr) catch unreachable;
    }

    return .{
        .data = rom,
    };
}

pub fn read(self: *const Cartridge, addr: u16) u8 {
    return self.data[addr];
}

pub fn write(self: *Cartridge, addr: u16, value: u8) void {
    _ = addr; // autofix
    _ = value; // autofix
    _ = self; // autofix
}

pub fn ramRead(self: *const Cartridge, addr: u16) u8 {
    _ = self; // autofix
    _ = addr; // autofix
    return 0;
}

pub fn ramWrite(self: *Cartridge, addr: u16, value: u8) void {
    _ = self; // autofix
    _ = addr; // autofix
    _ = value; // autofix
}
