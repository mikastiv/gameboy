const Display = @This();

const std = @import("std");

pub const Registers = @import("display/Registers.zig");
pub const Frame = @import("display/Frame.zig");

pub const frequency_hz = 59.72;

pub const OamEntry = packed struct(u32) {
    y: u8,
    x: u8,
    tile_index: u8,
    attr: packed struct(u8) {
        cgb_palette: u3,
        cgb_bank: u1,
        dmg_palette: u1,
        x_flip: bool,
        y_flip: bool,
        priority: bool,
    },
};

const oam_size = 40;

const vram_size = 0x2000;
const vram_mask = vram_size - 1;

regs: Registers,
frame: Frame,
oam: [oam_size]OamEntry,
vram: [vram_size]u8,

pub const init: Display = .{
    .regs = .init,
    .frame = .init,
    .oam = std.mem.zeroes([oam_size]OamEntry),
    .vram = @splat(0),
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

pub fn oamRead(self: *const Display, addr: u16) u8 {
    const ptr = std.mem.sliceAsBytes(&self.oam);
    return switch (addr & 0xFF) {
        0x00...0x9F => ptr[addr & 0xFF],
        0xA0...0xFF => 0x00, // TODO: OAM corruption
        else => unreachable,
    };
}

pub fn oamWrite(self: *Display, addr: u16, value: u8) void {
    const ptr = std.mem.sliceAsBytes(&self.oam);
    switch (addr & 0xFF) {
        0x00...0x9F => ptr[addr & 0xFF] = value,
        0xA0...0xFF => {},
        else => unreachable,
    }
}

pub fn vramRead(self: *const Display, addr: u16) u8 {
    return self.vram[addr & vram_mask];
}

pub fn vramWrite(self: *Display, addr: u16, value: u8) void {
    self.vram[addr & vram_mask] = value;
}

pub fn tick(self: *Display) void {
    _ = self; // autofix
}
