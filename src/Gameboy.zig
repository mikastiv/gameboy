const Gameboy = @This();

const std = @import("std");
const c = @import("c.zig");
const Cpu = @import("Cpu.zig");
const Apu = @import("Apu.zig");
const Bus = @import("Bus.zig");
const Display = @import("Display.zig");
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

pub fn create(rom: []const u8) Gameboy {
    return .{
        .cpu = .init,
        .apu = .init,
        .bus = .init,
        .cartridge = Cartridge.init(rom),
        .joypad = .init,
        .interrupts = .init,
        .timer = .init,
        .display = .init,
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

    self.display.interrupts = &self.interrupts;

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
            // std.Thread.sleep(std.time.ns_per_ms * 10);

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

                try sdl.renderFrame(&self.display.frame.pixels);
                try tile_viewer.update(&self.bus);

                break;
            }
        }
    }
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
                    c.SDLK_U => Joypad.Button.a,
                    c.SDLK_I => Joypad.Button.b,
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
