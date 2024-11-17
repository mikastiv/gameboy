const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const disassemble = b.option(bool, "disassemble", "Disassemble executed instructions") orelse false;
    const tiles_viewer = b.option(bool, "tiles_viewer", "Show the tiles viewer") orelse false;
    const blargg_serial_output = b.option(bool, "blargg_serial_output", "Print Blargg tests serial output in stderr") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "disassemble", disassemble);
    build_options.addOption(bool, "tiles_viewer", tiles_viewer);
    build_options.addOption(bool, "blargg_serial_output", blargg_serial_output);

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
    exe.linkLibrary(sdl.artifact("SDL3"));

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
