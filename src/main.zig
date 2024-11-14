const std = @import("std");
const c = @import("c.zig");
const Gameboy = @import("Gameboy.zig");

pub fn main() !void {
    const stderr = std.io.getStdErr().writer();

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    if (args.len != 2) {
        const exe = if (args.len > 0) args[0] else "./gameboy";
        try stderr.print("usage: {s} <rom file>\n", .{exe});
        return error.NoRomProvided;
    }

    const rom = try loadRom(args[1]);

    if (!c.SDL_Init(c.SDL_INIT_VIDEO))
        return error.SdlInit;
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Gameboy", 800, 600, 0) orelse
        return error.SdlWindowCreation;
    defer c.SDL_DestroyWindow(window);

    var gb = Gameboy.create(rom);
    gb.init();
    try gb.run();
}

fn loadRom(path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const max_size = 1024 * 1024 * 32;
    const rom = try file.readToEndAllocOptions(
        std.heap.page_allocator,
        max_size,
        stat.size,
        1,
        null,
    );

    return rom;
}

test {
    _ = @import("Cpu.zig");
    _ = @import("math.zig");
}
