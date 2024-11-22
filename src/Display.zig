const Display = @This();

const std = @import("std");
const Interrupts = @import("Interrupts.zig");
const Fifo = @import("display/Fifo.zig");
const Fetcher = @import("display/Fetcher.zig");

pub const Registers = @import("display/Registers.zig");
pub const Frame = @import("display/Frame.zig");

pub const frequency_hz = 59.72;

const colors: [4]Frame.Pixel = .{
    .{ .r = 0x0F, .g = 0x38, .b = 0x0F, .a = 0xFF },
    .{ .r = 0x30, .g = 0x62, .b = 0x30, .a = 0xFF },
    .{ .r = 0x8B, .g = 0xAC, .b = 0x0F, .a = 0xFF },
    .{ .r = 0x9B, .g = 0xBC, .b = 0x0F, .a = 0xFF },
};

const dots_per_line = 456;
const scanlines = 154;

const oam_size = 40;

const vram_size = 0x2000;
const vram_mask = vram_size - 1;

const InterruptSource = enum { oam, hblank, vblank, lyc };

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
interrupts: *Interrupts,
interrupt_line: bool,
fifo: Fifo,
fetcher: Fetcher,
scanline_drawn: bool,

dot: u16,
pixel_x: u8,

bg_colors: [4]Frame.Pixel,
obj_colors: [2][4]Frame.Pixel,

pub const init: Display = .{
    .regs = .init,
    .frame = .init,
    .oam = std.mem.zeroes([oam_size]OamEntry),
    .vram = @splat(0),
    .interrupts = undefined,
    .interrupt_line = false,
    .fifo = .init,
    .fetcher = .init,
    .scanline_drawn = false,
    .dot = 0,
    .pixel_x = 0,
    .bg_colors = @splat(Frame.Pixel.black),
    .obj_colors = @splat(@splat(Frame.Pixel.black)),
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
        0xFF47 => {
            self.regs.bg_pal = value;
            updatePalette(value, &self.bg_colors);
        },
        0xFF48, 0xFF49 => {
            self.regs.obj_pal[addr & 1] = value;
            updatePalette(value & 0xFC, &self.obj_colors[addr & 1]);
        },
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
    if (self.regs.stat.mode == .drawing) {
        return 0xFF;
    } else {
        return self.vram[addr & vram_mask];
    }
}

pub fn vramWrite(self: *Display, addr: u16, value: u8) void {
    if (self.regs.stat.mode != .drawing) {
        self.vram[addr & vram_mask] = value;
    }
}

pub fn tick(self: *Display) void {
    if (!self.regs.ctrl.lcd_on) {
        self.regs.stat.mode = .hblank;
        self.regs.ly = 0;
        return;
    }

    switch (self.regs.stat.mode) {
        .hblank => self.hblankTick(),
        .vblank => self.vblankTick(),
        .oam_scan => self.oamScanTick(),
        .drawing => self.drawingTick(),
    }
}

fn updatePalette(data: u8, pal: *[4]Frame.Pixel) void {
    inline for (0..4) |i| {
        pal[i] = colors[(data >> @truncate(i * 2)) & 0x03];
    }
}

fn triggerInterrupt(self: *Display, comptime source: InterruptSource) void {
    const old_line = self.interrupt_line;

    switch (source) {
        .oam => self.interrupt_line = self.regs.stat.oam_int,
        .hblank => self.interrupt_line = self.regs.stat.hblank_int,
        .vblank => self.interrupt_line = self.regs.stat.vblank_int,
        .lyc => self.interrupt_line = self.regs.stat.match_int,
    }

    if (!old_line and self.interrupt_line) {
        self.interrupts.request(.lcd);
    }
}

fn incrementLy(self: *Display) void {
    self.regs.ly += 1;

    if (self.regs.ly == self.regs.lyc) {
        self.regs.stat.match_flag = true;
        self.triggerInterrupt(.lyc);
    } else {
        self.regs.stat.match_flag = false;
    }
}

fn oamScanTick(self: *Display) void {
    self.dot += 1;

    if (self.dot >= 80) {
        self.regs.stat.mode = .drawing;
        // self.fetcher.clear();
        // self.fifo.clear();
    }
}

fn drawScanline(self: *Display) void {
    std.debug.assert(!self.scanline_drawn);

    const y = self.regs.ly;
    for (0..Frame.width / 8) |x| {
        const addr =
            self.regs.ctrl.bgTileMapArea() +
            x +
            ((self.regs.scx / 8) & 0x1F) +
            32 * @as(u16, ((self.regs.ly +% self.regs.scy) / 8));

        var tile_id = self.vram[addr];
        if (self.regs.ctrl.bgw_data) tile_id +%= 128;

        const addr_lo =
            self.regs.ctrl.bgwTileDataArea() +
            2 * ((self.regs.ly +% self.regs.scy) % 8);
        var tile_lo = self.vram[addr_lo];

        const addr_hi =
            self.regs.ctrl.bgwTileDataArea() +
            @as(u16, tile_id) * 16 +
            2 * ((self.regs.ly +% self.regs.scy) % 8) +
            1;
        var tile_hi = self.vram[addr_hi];

        tile_lo = @bitReverse(tile_lo);
        tile_hi = @bitReverse(tile_hi);
        for (0..8) |i| {
            const pixel = (tile_lo & 1) | ((tile_hi & 1) << 1);
            const color = self.bg_colors[pixel];

            self.frame.putPixel(x * 8 + i, y, color);

            tile_lo >>= 1;
            tile_hi >>= 1;
        }
    }
}

fn drawingTick(self: *Display) void {
    self.dot += 1;
    self.interrupt_line = false;

    // self.fetcher.tick(self);
    // if (self.fifo.pop()) |entry| {
    //     self.frame.putPixel(self.pixel_x, self.regs.ly, self.bg_colors[entry.pixel]);
    //     self.pixel_x += 1;
    // }

    if (!self.scanline_drawn) {
        self.drawScanline();
        self.scanline_drawn = true;
    }

    if (self.dot >= 80 + 172) {
        self.regs.stat.mode = .hblank;
        self.triggerInterrupt(.hblank);
        self.pixel_x = 0;
    }
}

fn hblankTick(self: *Display) void {
    self.dot += 1;

    if (self.dot >= dots_per_line) {
        self.dot = 0;
        self.scanline_drawn = false;
        self.incrementLy();

        if (self.regs.ly >= Frame.height) {
            self.regs.stat.mode = .vblank;
            self.triggerInterrupt(.vblank);
        } else {
            self.regs.stat.mode = .oam_scan;
            self.triggerInterrupt(.oam);
        }
    }
}

fn vblankTick(self: *Display) void {
    self.dot += 1;

    if (self.dot >= dots_per_line) {
        self.dot = 0;
        self.incrementLy();

        if (self.regs.ly >= scanlines) {
            self.regs.ly = 0;
            self.regs.stat.mode = .oam_scan;
            self.triggerInterrupt(.oam);
        }
    }
}
