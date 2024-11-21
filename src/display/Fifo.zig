const Fifo = @This();
const std = @import("std");

const entry_count = 8;

pub const Palette = enum { bg, sp0, sp1 };

pub const Entry = struct {
    pal: Palette,
    pixel: u8,

    pub const init: Entry = .{
        .pal = .bg,
        .pixel = 0,
    };
};

items: [entry_count]Entry,
idx: usize,

pub const init: Fifo = .{
    .items = @splat(.init),
    .idx = entry_count,
};

pub fn pop(self: *Fifo) ?Entry {
    if (self.size() == 0) {
        return null;
    }

    defer self.idx += 1;
    return self.items[self.idx];
}

pub fn push(self: *Fifo, lo: u8, hi: u8, pal: Palette) void {
    std.debug.assert(self.size() == 0);

    var lower = lo;
    var higher = hi;

    inline for (0..8) |i| {
        const pixel = (lower & 0x80) >> 7 | (higher & 0x80) >> 6;
        self.items[i] = .{
            .pal = pal,
            .pixel = pixel,
        };

        lower <<= 1;
        higher <<= 1;
    }

    self.idx = 0;
}

pub fn size(self: *const Fifo) usize {
    return self.items.len - self.idx;
}

pub fn clear(self: *Fifo) void {
    self.idx = 0;
}
