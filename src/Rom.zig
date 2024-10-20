const std = @import("std");

const Rom = @This();

pub const Header = @import("rom/Header.zig");

data: []const u8,

pub fn init(rom: []const u8) Rom {
    return .{
        .data = rom,
    };
}
