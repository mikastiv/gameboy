const std = @import("std");
const SdlContext = @import("SdlContext.zig");
const Gameboy = @import("Gameboy.zig");
const TilesViewer = @import("TilesViewer.zig");

pub fn main() !void {
    const stderr = std.io.getStdErr().writer();

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    if (args.len != 2) {
        const exe = if (args.len > 0) args[0] else "./gameboy";
        try stderr.print("usage: {s} <rom file>\n", .{exe});
        return error.NoRomProvided;
    }

    const rom = try loadRom(args[1]);

    const sdl = try SdlContext.init("Gameboy", 800, 600, Gameboy.Frame.width, Gameboy.Frame.height);
    defer sdl.deinit();

    const tile_viewer = try TilesViewer.init(sdl.window);
    defer tile_viewer.deinit();

    var gb = try Gameboy.create(rom);
    gb.init();
    try gb.run(sdl, tile_viewer);
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
        .@"1",
        null,
    );

    return rom;
}

test {
    _ = @import("Cpu.zig");
    _ = @import("math.zig");
}
