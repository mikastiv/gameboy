const Fetcher = @This();

const std = @import("std");
const Fifo = @import("Fifo.zig");

pub const State = enum(u8) {
    tile_id_1,
    tile_id_2,
    data_lo_1,
    data_lo_2,
    data_hi_1,
    data_hi_2,
    idle_1,
    idle_2,
    push_1,
    push_2,

    const count = std.enums.values(State).len;
};

state: State,

pub const init: Fetcher = .{
    .state = .tile_id_1,
};

pub fn tick(self: *Fetcher, fifo: *Fifo) void {
    switch (self.state) {
        .tile_id_1 => {},
        .tile_id_2 => {},
        .data_lo_1 => {},
        .data_lo_2 => {},
        .data_hi_1 => {},
        .data_hi_2 => {},
        .idle_1 => {},
        .idle_2 => {},
        .push_1 => {},
        .push_2 => {
            if (fifo.size() == 0) {
                fifo.push(0, 0, .bg);
            }
        },
    }

    const next_state = @intFromEnum(self.state) % State.count;
    self.state = @enumFromInt(next_state);
}

pub fn clear(self: *Fetcher) void {
    self.* = .init;
}
