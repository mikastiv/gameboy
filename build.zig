const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const disassemble = b.option(bool, "disassemble", "Disassemble executed instructions") orelse false;
    const tiles_viewer = b.option(bool, "tiles_viewer", "Show the tiles viewer") orelse false;
    const blargg_output = b.option(bool, "blargg_output", "Print Blargg's tests serial output in stderr") orelse false;
    const green_palette = b.option(bool, "green_palette", "Use green palette") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "disassemble", disassemble);
    build_options.addOption(bool, "tiles_viewer", tiles_viewer);
    build_options.addOption(bool, "blargg_output", blargg_output);
    build_options.addOption(bool, "green_palette", green_palette);

    const bootrom_file = try std.fs.cwd().openFile("bootrom/dmgboot", .{});
    defer bootrom_file.close();

    const raw_bootrom = try bootrom_file.readToEndAlloc(b.allocator, 1024 * 2);
    var fba = std.io.fixedBufferStream(raw_bootrom);

    var bootrom_out = std.ArrayList(u8).init(b.allocator);
    try std.compress.zlib.decompress(fba.reader(), bootrom_out.writer());

    const wf = b.addWriteFiles();
    const bootrom = wf.add("bootrom.bin", bootrom_out.items);

    const sdl = b.dependency("SDL", .{
        .target = target,
        .optimize = .ReleaseFast,
    });

    const exe = b.addExecutable(.{
        .name = "gameboy",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addOptions("build_options", build_options);
    exe.root_module.addAnonymousImport("bootrom", .{ .root_source_file = bootrom });
    exe.linkLibrary(sdl.artifact("SDL3"));

    if (builtin.os.tag == .windows) {
        exe.linkSystemLibrary("kernel32");
    }

    b.installArtifact(exe);

    const fmt_cmd = b.addFmt(.{ .paths = &.{ "src", "build.zig" } });
    const fmt_step = b.step("fmt", "Format every files");
    fmt_step.dependOn(&fmt_cmd.step);

    b.default_step.dependOn(&fmt_cmd.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
