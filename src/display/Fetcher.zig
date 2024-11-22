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
    idle_1,
    idle_2,
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
            const map_y: u16 = display.regs.ly +% display.regs.scy;
            const map_x = ((display.regs.scx / 8) + self.x) & 0x1F;
            const addr =
                display.regs.ctrl.bgTileMapArea() +
                map_x +
                32 * (map_y / 8);
            self.tile_id = display.vram[addr];

            if (!display.regs.ctrl.bgw_data) self.tile_id +%= 128;

            self.state = .tile_id_2;
        },
        .tile_id_2 => {
            self.state = .tile_lo_1;
        },
        .tile_lo_1 => {
            const tile_offset = @as(u16, self.tile_id) * 16;
            const map_y: u16 = display.regs.ly +% display.regs.scy;
            const tile_y = (map_y % 8) * 2;
            const addr = display.regs.ctrl.bgwTileDataArea() + tile_offset + tile_y;
            self.tile_lo = display.vram[addr];

            self.state = .tile_lo_2;
        },
        .tile_lo_2 => {
            self.state = .tile_hi_1;
        },
        .tile_hi_1 => {
            const tile_offset = @as(u16, self.tile_id) * 16;
            const map_y: u16 = display.regs.ly +% display.regs.scy;
            const tile_y = (map_y % 8) * 2;
            const addr = display.regs.ctrl.bgwTileDataArea() + tile_offset + tile_y + 1;
            self.tile_hi = display.vram[addr];

            self.state = .tile_hi_2;
        },
        .tile_hi_2 => {
            self.state = .push;
        },
        .idle_1 => self.state = .idle_2,
        .idle_2 => self.state = .push,
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
