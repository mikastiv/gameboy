const Fetcher = @This();

const std = @import("std");
const Display = @import("../Display.zig");

pub const State = enum {
    tile_id_1,
    tile_id_2,
    tile_lo_1,
    tile_lo_2,
    tile_hi_1,
    tile_hi_2,
    push,

    const count = std.enums.values(State).len;
};

state: State,
tile_id: u8,
tile_lo: u8,
tile_hi: u8,
x: u8,

pub const init: Fetcher = .{
    .state = .tile_id_1,
    .tile_id = 0,
    .tile_lo = 0,
    .tile_hi = 0,
    .x = 0,
};

pub fn tick(self: *Fetcher, display: *Display) void {
    switch (self.state) {
        .tile_id_1 => {
            const addr =
                display.regs.ctrl.bgTileMapArea() +
                self.x +
                ((display.regs.scx / 8) & 0x1F) +
                32 * @as(u16, ((display.regs.ly +% display.regs.scy) / 8));
            self.tile_id = display.vram[addr];

            if (display.regs.ctrl.bgw_data) self.tile_id +%= 128;

            self.state = .tile_id_2;
        },
        .tile_id_2 => {
            self.state = .tile_lo_1;
        },
        .tile_lo_1 => {
            const addr =
                display.regs.ctrl.bgwTileDataArea() +
                2 * ((display.regs.ly +% display.regs.scy) % 8);
            self.tile_lo = display.vram[addr];

            self.state = .tile_lo_2;
        },
        .tile_lo_2 => {
            self.state = .tile_hi_1;
        },
        .tile_hi_1 => {
            const addr =
                display.regs.ctrl.bgwTileDataArea() +
                @as(u16, self.tile_id) * 16 +
                2 * ((display.regs.ly +% display.regs.scy) % 8) +
                1;
            self.tile_hi = display.vram[addr];

            self.state = .tile_hi_2;
        },
        .tile_hi_2 => {
            self.state = .push;
        },
        .push => {
            if (display.fifo.size() == 0) {
                display.fifo.push(self.tile_lo, self.tile_hi, .bg);
                self.x += 1;
                self.state = .tile_id_1;
            }
        },
    }
}

pub fn clear(self: *Fetcher) void {
    self.* = .init;
}
