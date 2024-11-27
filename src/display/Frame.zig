const Frame = @This();

const std = @import("std");

pub const width = 160;
pub const height = 144;
pub const size = width * height * @sizeOf(Pixel);

pub const Pixel = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const black: Pixel = .{
        .r = 0,
        .g = 0,
        .b = 0,
        .a = 0xFF,
    };
};

comptime {
    std.debug.assert(@sizeOf(Pixel) == 4);
}

pixels: [size]u8,

pub const init: Frame = .{
    .pixels = @splat(0),
};

pub fn putPixel(self: *Frame, x: usize, y: usize, pixel: Pixel) void {
    std.debug.assert(x < width);
    std.debug.assert(y < height);

    const pixel_size = @sizeOf(Pixel);
    const index = y * width * pixel_size + x * pixel_size;

    const ptr = std.mem.bytesAsValue(Pixel, self.pixels[index .. index + pixel_size]);
    ptr.* = pixel;
}
