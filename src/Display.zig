const Display = @This();

pub const Frame = @import("display/Frame.zig");

pub const frequency_hz = 59.72;

frame: Frame,

pub const init: Display = .{
    .frame = .init,
};

pub fn read(self: *const Display, addr: u16) u8 {
    _ = addr; // autofix
    _ = self; // autofix
    return 0;
}

pub fn write(self: *Display, addr: u16, value: u8) void {
    _ = self; // autofix
    _ = addr; // autofix
    _ = value; // autofix
}
