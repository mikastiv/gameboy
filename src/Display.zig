const Display = @This();

const std = @import("std");

pub const Registers = @import("display/Registers.zig");
pub const Frame = @import("display/Frame.zig");

pub const frequency_hz = 59.72;

const dots_per_line = 456;
const scanlines = 154;

const oam_size = 40;

const vram_size = 0x2000;
const vram_mask = vram_size - 1;

const OamEntry = packed struct(u32) {
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

regs: Registers,
frame: Frame,
oam: [oam_size]OamEntry,
vram: [vram_size]u8,

dot: u16,

pub const init: Display = .{
    .regs = .init,
    .frame = .init,
    .oam = std.mem.zeroes([oam_size]OamEntry),
    .vram = @splat(0),
    .dot = 0,
};

pub fn read(self: *const Display, addr: u16) u8 {
    return switch (addr) {
        0xFF40 => @bitCast(self.regs.ctrl),
        0xFF41 => @as(u8, @bitCast(self.regs.stat)) | 0x80,
        0xFF42 => self.regs.scy,
        0xFF43 => self.regs.scx,
        0xFF44 => self.regs.ly,
        0xFF45 => self.regs.lyc,
        0xFF47 => self.regs.bg_pal,
        0xFF48, 0xFF49 => self.regs.obj_pal[addr & 1],
        0xFF4A => self.regs.wy,
        0xFF4B => self.regs.wx,
        else => blk: {
            std.log.debug("unimplemented read ${x:0>4}", .{addr});
            break :blk 0;
        },
    };
}

pub fn write(self: *Display, addr: u16, value: u8) void {
    switch (addr) {
        0xFF40 => self.regs.ctrl = @bitCast(value),
        0xFF41 => {
            const old = self.regs.stat;
            self.regs.stat = @bitCast(value | 0x80);
            self.regs.stat.mode = old.mode; // read-only
            self.regs.stat.match_flag = old.match_flag; // read-only
        },
        0xFF42 => self.regs.scy = value,
        0xFF43 => self.regs.scx = value,
        0xFF44 => {}, // ly read-only
        0xFF45 => self.regs.lyc = value,
        0xFF47 => self.regs.bg_pal = value,
        0xFF48, 0xFF49 => self.regs.obj_pal[addr & 1] = value,
        0xFF4A => self.regs.wy = value,
        0xFF4B => self.regs.wx = value,
        else => std.log.debug("unimplemented write ${x:0>4}, #${x:0>2}", .{ addr, value }),
    }
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
    switch (self.regs.stat.mode) {
        .hblank => self.hblankTick(),
        .vblank => self.vblankTick(),
        .oam_scan => self.oamScanTick(),
        .drawing => self.drawingTick(),
    }
}

fn oamScanTick(self: *Display) void {
    self.dot += 1;

    if (self.dot >= 80) {
        self.regs.stat.mode = .drawing;
    }
}

fn drawingTick(self: *Display) void {
    self.dot += 1;

    if (self.dot >= 80 + 172) {
        self.regs.stat.mode = .hblank;
    }
}

fn hblankTick(self: *Display) void {
    self.dot += 1;

    if (self.dot >= dots_per_line) {
        self.dot = 0;
        self.regs.ly += 1;

        if (self.regs.ly >= Frame.height) {
            self.regs.stat.mode = .vblank;
        } else {
            self.regs.stat.mode = .oam_scan;
        }
    }
}

fn vblankTick(self: *Display) void {
    self.dot += 1;

    if (self.dot >= dots_per_line) {
        self.dot = 0;
        self.regs.ly += 1;

        if (self.regs.ly >= scanlines) {
            self.regs.ly = 0;
            self.regs.stat.mode = .oam_scan;
        }
    }
}
