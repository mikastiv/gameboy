const std = @import("std");
const Cpu = @import("Cpu.zig");
const Display = @import("Display.zig");

const Gameboy = @This();

cpu: Cpu,
display: Display,

pub fn init(rom: []const u8) Gameboy {
    return .{
        .cpu = Cpu.init(rom),
        .display = .{},
    };
}

pub fn run(self: *Gameboy) !void {
    const sec_per_frame = 1.0 / Display.frequency_hz;
    const ns_per_frame = sec_per_frame * std.time.ns_per_s;
    const clocks_per_frame = Cpu.frequency_hz * sec_per_frame;

    var timer = try std.time.Timer.start();
    var frames: u64 = 0;
    while (true) {
        self.cpu.step();
        std.Thread.sleep(std.time.ns_per_ms * 100);

        const cycles: f64 = @floatFromInt(self.cpu.bus.cycles);
        const total_frames: u64 = @intFromFloat(cycles / clocks_per_frame);

        if (frames != total_frames) {
            frames = total_frames;

            const elapsed_ns = timer.read();
            const expected_ns: u64 = @intFromFloat(ns_per_frame);
            if (expected_ns > elapsed_ns) {
                const sleep_ns = expected_ns - elapsed_ns;

                const start = try std.time.Instant.now();
                var now = try std.time.Instant.now();
                while (now.since(start) < sleep_ns) {
                    now = try std.time.Instant.now();
                }

                // std.Thread.sleep(sleep_ns);
            }

            timer.reset();
        }
    }
}
