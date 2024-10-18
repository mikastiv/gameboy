const std = @import("std");
const Gameboy = @import("Gameboy.zig");

pub fn main() !void {
    var gb = Gameboy.init();
    gb.cpu.step();
}

test {
    _ = @import("cpu/Cpu.zig");
}
