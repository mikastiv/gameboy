const Gameboy = @This();

const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");
const Cpu = @import("Cpu.zig");
const Apu = @import("Apu.zig");
const Bus = @import("Bus.zig");
const Display = @import("Display.zig");
const Dma = @import("Dma.zig");
const Cartridge = @import("Cartridge.zig");
const Joypad = @import("Joypad.zig");
const Interrupts = @import("Interrupts.zig");
const Timer = @import("Timer.zig");
const SdlContext = @import("SdlContext.zig");
const TilesViewer = @import("TilesViewer.zig");

pub const Frame = Display.Frame;

cpu: Cpu,
apu: Apu,
bus: Bus,
cartridge: Cartridge,
joypad: Joypad,
interrupts: Interrupts,
timer: Timer,
display: Display,
dma: Dma,

pub fn create(rom: []const u8) !Gameboy {
    return .{
        .cpu = .init,
        .apu = .init,
        .bus = .init,
        .cartridge = try Cartridge.init(rom),
        .joypad = .init,
        .interrupts = .init,
        .timer = .init,
        .display = .init,
        .dma = .init,
    };
}

pub fn init(self: *Gameboy) void {
    self.cpu.bus = &self.bus;

    self.bus.apu = &self.apu;
    self.bus.cartridge = &self.cartridge;
    self.bus.joypad = &self.joypad;
    self.bus.interrupts = &self.interrupts;
    self.bus.timer = &self.timer;
    self.bus.display = &self.display;
    self.bus.dma = &self.dma;

    self.display.bus = &self.bus;

    self.dma.cpu = &self.cpu;
    self.dma.bus = &self.bus;
    self.dma.display = &self.display;

    self.joypad.interrupts = &self.interrupts;

    self.timer.interrupts = &self.interrupts;
}

pub fn run(self: *Gameboy, sdl: SdlContext, tile_viewer: TilesViewer) !void {
    const sec_per_frame = 1.0 / Display.frequency_hz;
    const ns_per_frame = sec_per_frame * std.time.ns_per_s;
    const clocks_per_frame = Cpu.frequency_hz * sec_per_frame;

    var timer = try std.time.Timer.start();
    var frames: u64 = 0;
    while (true) {
        var quit = false;
        self.pollEvents(&quit);
        if (quit) break;

        while (true) {
            self.cpu.step();

            const cycles: f64 = @floatFromInt(self.cpu.bus.cycles);
            const total_frames: u64 = @intFromFloat(cycles / clocks_per_frame);

            if (frames != total_frames) {
                frames = total_frames;

                const elapsed_ns = timer.read();
                const expected_ns: u64 = @intFromFloat(ns_per_frame);
                if (expected_ns > elapsed_ns) {
                    sleep(expected_ns - elapsed_ns);
                }

                timer.reset();

                const frame = self.display.displayFrame();
                try sdl.renderFrame(&frame.pixels);
                try tile_viewer.update(&self.display.vram);

                break;
            }
        }
    }

    try self.cartridge.saveRam();
}

fn pollEvents(self: *Gameboy, quit: *bool) void {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event)) {
        switch (event.type) {
            c.SDL_EVENT_QUIT => {
                quit.* = true;
                break;
            },
            c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
                if (event.key.repeat) continue;

                const key = event.key.key;

                if (key == c.SDLK_ESCAPE) {
                    quit.* = true;
                    break;
                }

                const gb_button = switch (key) {
                    c.SDLK_W => Joypad.Button.up,
                    c.SDLK_S => Joypad.Button.down,
                    c.SDLK_A => Joypad.Button.left,
                    c.SDLK_D => Joypad.Button.right,
                    c.SDLK_I => Joypad.Button.a,
                    c.SDLK_U => Joypad.Button.b,
                    c.SDLK_J => Joypad.Button.select,
                    c.SDLK_K => Joypad.Button.start,
                    else => null,
                };

                if (gb_button) |button| {
                    const is_up = event.key.type == c.SDL_EVENT_KEY_UP;
                    self.joypad.setButton(button, is_up);
                }
            },
            else => {},
        }
    }
}

extern "kernel32" fn CreateWaitableTimerA(
    lpTimerAttributes: ?*std.os.windows.SECURITY_ATTRIBUTES,
    bManualReset: std.os.windows.BOOL,
    lpTimerName: ?[*:0]const u8,
) callconv(std.os.windows.WINAPI) ?std.os.windows.HANDLE;

extern "kernel32" fn SetWaitableTimer(
    hTimer: ?std.os.windows.HANDLE,
    lpDueTime: ?*const std.os.windows.LARGE_INTEGER,
    lPeriod: i32,
    pfnCompletionRoutine: ?PTIMERAPCROUTINE,
    lpArgToCompletionRoutine: ?*anyopaque,
    fResume: std.os.windows.BOOL,
) callconv(std.os.windows.WINAPI) std.os.windows.BOOL;

const PTIMERAPCROUTINE = *const fn (
    lpArgToCompletionRoutine: ?*anyopaque,
    dwTimerLowValue: u32,
    dwTimerHighValue: u32,
) callconv(std.os.windows.WINAPI) void;

fn sleep(ns: u64) void {
    if (builtin.os.tag == .windows) {
        const timer = CreateWaitableTimerA(null, std.os.windows.TRUE, null) orelse return;
        defer std.os.windows.CloseHandle(timer);

        var time: std.os.windows.LARGE_INTEGER = @intCast(ns / 100);
        time = -time;

        _ = SetWaitableTimer(timer, &time, 0, null, null, std.os.windows.FALSE);
        std.os.windows.WaitForSingleObject(timer, std.os.windows.INFINITE) catch {};
    } else {
        std.Thread.sleep(ns);
    }
}
