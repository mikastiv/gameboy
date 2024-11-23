const Dma = @This();

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
    .byte = 0xA0,
    .cpu = undefined,
    .bus = undefined,
    .display = undefined,
};

pub fn read(self: *const Dma) u8 {
    return @truncate(self.page >> 8);
}

pub fn write(self: *Dma, value: u8) void {
    self.page = @as(u16, value) << 8;
    self.byte = 0x00;
}

pub fn tick(self: *Dma) void {
    if (self.cpu.halted) return;
    if (!self.active()) return;

    const value = self.bus.peek(self.page | self.byte);
    self.display.oamWrite(self.byte, value);

    self.byte += 1;
}

pub fn active(self: *const Dma) bool {
    return self.byte < 0xA0;
}
