const Cpu = @import("cpu/Cpu.zig");

const Gameboy = @This();

cpu: Cpu,

pub fn init(rom: []const u8) Gameboy {
    return .{
        .cpu = Cpu.init(rom),
    };
}
