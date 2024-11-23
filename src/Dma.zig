const Dma = @This();

const std = @import("std");
const Cpu = @import("Cpu.zig");
const Bus = @import("Bus.zig");
const Display = @import("Display.zig");

page: u16,
byte: u8,
cpu: *Cpu,
bus: *Bus,
display: *Display,

pub const init: Dma = .{
    .page = 0x00,
    .byte = 0xFF,
    .cpu = undefined,
    .bus = undefined,
    .display = undefined,
};

pub fn read(self: *const Dma) u8 {
    return @truncate(self.page >> 8);
}

pub fn write(self: *Dma, value: u8) void {
    self.page = @as(u16, value) << 8;
    self.byte = 0xFF;
}

pub fn tick(self: *Dma) void {
    if (self.cpu.halted) return;
    if (!self.active()) return;

    if (self.byte < 0xA0) {
        const addr = self.page | self.byte;
        const value = self.bus.peek(addr);
        const ptr = std.mem.sliceAsBytes(&self.display.oam);
        ptr[self.byte] = value;
    }

    self.byte +%= 1;
}

pub fn active(self: *const Dma) bool {
    return self.byte != 0xA0;
}
