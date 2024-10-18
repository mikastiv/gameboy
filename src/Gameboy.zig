const Cpu = @import("cpu/Cpu.zig");

const Gameboy = @This();

cpu: Cpu,

pub fn init() Gameboy {
    return .{
        .cpu = .init,
    };
}
