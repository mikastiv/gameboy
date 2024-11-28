const Display = @This();

const std = @import("std");
const cast = @import("math.zig").cast;
const build_options = @import("build_options");
const Interrupts = @import("Interrupts.zig");
const Dma = @import("Dma.zig");
const Fifo = @import("display/Fifo.zig");
const Fetcher = @import("display/Fetcher.zig");

pub const Registers = @import("display/Registers.zig");
pub const Mode = Registers.Mode;
pub const Frame = @import("display/Frame.zig");

pub const frequency_hz = 59.72;

const green_palette: [4]Frame.Pixel = .{
    .{ .r = 0x7F, .g = 0x86, .b = 0x0F, .a = 0xFF },
    .{ .r = 0x57, .g = 0x7C, .b = 0x44, .a = 0xFF },
    .{ .r = 0x36, .g = 0x5D, .b = 0x48, .a = 0xFF },
    .{ .r = 0x2A, .g = 0x45, .b = 0x3B, .a = 0xFF },
};

const gray_palette: [4]Frame.Pixel = .{
    .{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF },
    .{ .r = 0xAA, .g = 0xAA, .b = 0xAA, .a = 0xFF },
    .{ .r = 0x55, .g = 0x55, .b = 0x55, .a = 0xFF },
    .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xFF },
};

const colors: [4]Frame.Pixel = switch (build_options.green_palette) {
    true => green_palette,
    false => gray_palette,
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
    tile_id: u8,
    attr: packed struct(u8) {
        cgb_palette: u3,
        cgb_bank: u1,
        dmg_palette: u1,
        x_flip: bool,
        y_flip: bool,
        priority: bool,
    },

    const init: OamEntry = .{
        .attr = .{
            .cgb_palette = 0,
            .cgb_bank = 0,
            .dmg_palette = 0,
            .x_flip = false,
            .y_flip = false,
            .priority = false,
        },
        .tile_id = 0,
        .x = 0,
        .y = 0,
    };
};

const IndexedOamEntry = struct {
    oam_entry: OamEntry,
    index: u32,

    const init: IndexedOamEntry = .{
        .oam_entry = .init,
        .index = 0,
    };

    fn lessThan(_: void, a: IndexedOamEntry, b: IndexedOamEntry) bool {
        if (a.oam_entry.x == b.oam_entry.x) {
            return a.index < b.index;
        } else {
            return a.oam_entry.x < b.oam_entry.x;
        }
    }
};

const BgPriority = std.StaticBitSet(Frame.width);

regs: Registers,
frames: [2]Frame,
current_frame: u64,
frame_num: u64,
oam: [oam_size]OamEntry,
vram: [vram_size]u8,
interrupts: *Interrupts,
dma: *Dma,
interrupt_line: bool,
fifo: Fifo,
fetcher: Fetcher,
scanline_drawn: bool,

dot: u16,
pixel_x: u8,
window_line: u8,
visible_sprites: [10]IndexedOamEntry,
visible_sprite_count: u32,

bg_priority: BgPriority,
bg_colors: [4]Frame.Pixel,
obj_colors: [2][4]Frame.Pixel,

pub const init: Display = .{
    .regs = .init,
    .frames = @splat(.init),
    .current_frame = 0,
    .frame_num = 0,
    .oam = @splat(.init),
    .vram = @splat(0),
    .interrupts = undefined,
    .dma = undefined,
    .interrupt_line = false,
    .fifo = .init,
    .fetcher = .init,
    .scanline_drawn = false,
    .dot = 0,
    .pixel_x = 0,
    .window_line = 0,
    .visible_sprites = @splat(.init),
    .visible_sprite_count = 0,
    .bg_priority = BgPriority.initEmpty(),
    .bg_colors = @splat(Frame.Pixel.black),
    .obj_colors = @splat(@splat(Frame.Pixel.black)),
};

pub fn read(self: *const Display, addr: u16) u8 {
    return switch (addr) {
        0xFF40 => @bitCast(self.regs.ctrl),
        0xFF41 => 0x80 | @as(u8, @bitCast(self.regs.stat)),
        0xFF42 => self.regs.scy,
        0xFF43 => self.regs.scx,
        0xFF44 => self.regs.ly,
        0xFF45 => self.regs.lyc,
        0xFF46 => self.dma.read(),
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
        0xFF40 => {
            const old = self.regs.ctrl;
            self.regs.ctrl = @bitCast(value);

            if (old.lcd_on != self.regs.ctrl.lcd_on) {
                self.dot = 0;
                self.regs.ly = 0;
                self.regs.stat.mode = .hblank;
            }
        },
        0xFF41 => {
            const old = self.regs.stat;
            self.regs.stat = @bitCast(0x80 | value);
            self.regs.stat.mode = old.mode; // read-only
            self.regs.stat.match_flag = old.match_flag; // read-only
        },
        0xFF42 => self.regs.scy = value,
        0xFF43 => self.regs.scx = value,
        0xFF44 => {}, // ly read-only
        0xFF45 => self.regs.lyc = value,
        0xFF46 => self.dma.write(value),
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
        0x00...0x9F => if (self.oamBlocked()) 0xFF else ptr[addr & 0xFF],
        0xA0...0xFF => 0xFF,
        else => unreachable,
    };
}

pub fn oamWrite(self: *Display, addr: u16, value: u8) void {
    const ptr = std.mem.sliceAsBytes(&self.oam);
    switch (addr & 0xFF) {
        0x00...0x9F => if (!self.oamBlocked()) {
            ptr[addr & 0xFF] = value;
        },
        0xA0...0xFF => {},
        else => unreachable,
    }
}

pub fn vramRead(self: *const Display, addr: u16) u8 {
    if (self.vramBlocked()) {
        return 0xFF;
    } else {
        return self.vram[addr & vram_mask];
    }
}

pub fn vramWrite(self: *Display, addr: u16, value: u8) void {
    if (!self.vramBlocked()) {
        self.vram[addr & vram_mask] = value;
    }
}

pub fn tick(self: *Display) void {
    if (!self.regs.ctrl.lcd_on) {
        return;
    }

    switch (self.regs.stat.mode) {
        .hblank => self.hblankTick(),
        .vblank => self.vblankTick(),
        .oam_scan => self.oamScanTick(),
        .drawing => self.drawingTick(),
    }
}

pub fn displayFrame(self: *const Display) *const Frame {
    const display_frame = (self.current_frame + 1) % self.frames.len;
    return &self.frames[display_frame];
}

fn vramBlocked(self: *const Display) bool {
    return self.regs.ctrl.lcd_on and self.regs.stat.mode == .drawing;
}

fn oamBlocked(self: *const Display) bool {
    return self.regs.ctrl.lcd_on and (self.regs.stat.mode == .oam_scan or self.regs.stat.mode == .drawing);
}

fn updatePalette(data: u8, pal: *[4]Frame.Pixel) void {
    inline for (0..4) |i| {
        pal[i] = colors[(data >> @truncate(i * 2)) & 0x03];
    }
}

fn statInterrupt(self: *Display, comptime source: InterruptSource) void {
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

fn windowVisible(self: *const Display) bool {
    return self.regs.ctrl.win_on and
        self.regs.wx < Frame.width + 7 and
        self.regs.wy < Frame.height and
        self.regs.wy <= self.regs.ly;
}

fn incrementLy(self: *Display) void {
    if (self.windowVisible()) {
        self.window_line += 1;
    }
    self.regs.ly += 1;

    if (self.regs.ly == self.regs.lyc) {
        self.regs.stat.match_flag = true;
        self.statInterrupt(.lyc);
    } else {
        self.regs.stat.match_flag = false;
    }
}

fn fetchVisibleSprites(self: *Display) void {
    const obj_size = self.regs.ctrl.objSize();

    self.visible_sprite_count = 0;
    for (&self.oam) |entry| {
        if (entry.x == 0) continue;

        const y = entry.y -% 16;
        if (self.regs.ly -% y < obj_size) {
            self.visible_sprites[self.visible_sprite_count] = .{
                .oam_entry = entry,
                .index = self.visible_sprite_count,
            };
            self.visible_sprite_count += 1;

            if (self.visible_sprite_count >= self.visible_sprites.len)
                break;
        }
    }

    std.mem.sort(IndexedOamEntry, self.visible_sprites[0..self.visible_sprite_count], {}, IndexedOamEntry.lessThan);
    std.mem.reverse(IndexedOamEntry, self.visible_sprites[0..self.visible_sprite_count]);
}

fn oamScanTick(self: *Display) void {
    if (self.dot == 0) {
        self.fetchVisibleSprites();
    }

    self.dot += 1;

    if (self.dot >= 80) {
        self.switchMode(.drawing);
    }
}

fn drawBackgroundLine(self: *Display) void {
    const area = self.regs.ctrl.bgTileMapArea();
    const map_y: u16 = self.regs.ly +% self.regs.scy;

    for (0..Frame.width) |pixel_x| {
        const map_x = cast(u8, pixel_x) +% self.regs.scx;
        const addr = area + (map_x / 8) + 32 * (map_y / 8);

        var tile_id = self.vram[addr];
        if (!self.regs.ctrl.bgw_data) tile_id +%= 128;

        const tile_offset = @as(u16, tile_id) * 16;
        const tile_y = (map_y % 8) * 2;
        const base_addr = self.regs.ctrl.bgwTileDataArea() + tile_offset;

        const addr_lo = base_addr + tile_y;
        const tile_lo = self.vram[addr_lo];

        const addr_hi = base_addr + tile_y + 1;
        const tile_hi = self.vram[addr_hi];

        const bit: u3 = @intCast(((map_x % 8) -% 7) *% 0xFF);
        const lo = (tile_lo >> bit) & 1;
        const hi = ((tile_hi >> bit) & 1) << 1;
        const pixel = hi | lo;
        const color = self.bg_colors[pixel];
        self.frames[self.current_frame].putPixel(pixel_x, self.regs.ly, color);
        self.bg_priority.setValue(pixel_x, pixel != 0);
    }
}

fn drawWindowLine(self: *Display) void {
    const area = self.regs.ctrl.winTileMapArea();
    const map_y: u16 = self.window_line;
    const x_offset = self.regs.wx - 7;
    const tile_count = (Frame.width / 8) -| (x_offset / 8);

    for (0..tile_count) |x| {
        const map_x = x;
        const addr = area + map_x + 32 * (map_y / 8);

        var tile_id = self.vram[addr];
        if (!self.regs.ctrl.bgw_data) tile_id +%= 128;

        const tile_offset = @as(u16, tile_id) * 16;
        const tile_y = (map_y % 8) * 2;
        const base_addr = self.regs.ctrl.bgwTileDataArea() + tile_offset;

        const addr_lo = base_addr + tile_y;
        var tile_lo = self.vram[addr_lo];

        const addr_hi = base_addr + tile_y + 1;
        var tile_hi = self.vram[addr_hi];

        tile_lo = @bitReverse(tile_lo);
        tile_hi = @bitReverse(tile_hi);
        for (0..8) |bit| {
            const pixel = (tile_lo & 1) | ((tile_hi & 1) << 1);
            const color = self.bg_colors[pixel];

            const pixel_x: u8 = x_offset + cast(u8, x) * 8 + cast(u8, bit);
            if (pixel_x < Frame.width) {
                self.frames[self.current_frame].putPixel(pixel_x, self.regs.ly, color);
                self.bg_priority.setValue(pixel_x, pixel != 0);
            }

            tile_lo >>= 1;
            tile_hi >>= 1;
        }
    }
}

var hit = false;
fn drawSpriteLine(self: *Display) void {
    const obj_mask: u8 = if (self.regs.ctrl.obj_size) 0xF else 0x7;

    for (self.visible_sprites[0..self.visible_sprite_count]) |entry| {
        var tile_y = (self.regs.ly -% entry.oam_entry.y -% 16) & obj_mask;
        if (entry.oam_entry.attr.y_flip) tile_y ^= obj_mask;

        var tile_id = entry.oam_entry.tile_id;
        if (self.regs.ctrl.obj_size) tile_id &= 0xFE;
        const base_addr = @as(u16, tile_id) * 16;

        const addr_lo = base_addr + tile_y * 2;
        var sprite_lo = self.vram[addr_lo];

        const addr_hi = base_addr + tile_y * 2 + 1;
        var sprite_hi = self.vram[addr_hi];

        if (!entry.oam_entry.attr.x_flip) {
            sprite_lo = @bitReverse(sprite_lo);
            sprite_hi = @bitReverse(sprite_hi);
        }

        for (0..8) |bit| {
            const pixel = (sprite_lo & 1) | ((sprite_hi & 1) << 1);
            const color = self.obj_colors[entry.oam_entry.attr.dmg_palette][pixel];

            const pixel_x: u8 = (entry.oam_entry.x -% 8) +% cast(u8, bit);
            if (pixel != 0 and pixel_x < Frame.width) {
                const bg_priority = self.bg_priority.isSet(pixel_x);
                if (!entry.oam_entry.attr.priority or !bg_priority) {
                    self.frames[self.current_frame].putPixel(pixel_x, self.regs.ly, color);
                }
            }

            sprite_lo >>= 1;
            sprite_hi >>= 1;
        }
    }
}

fn drawScanline(self: *Display) void {
    std.debug.assert(!self.scanline_drawn);

    if (self.regs.ctrl.bgw_on) {
        self.drawBackgroundLine();
        if (self.windowVisible()) {
            self.drawWindowLine();
        }
    } else {
        for (0..Frame.width) |x| {
            const col: usize = x;
            const row: usize = self.regs.ly;
            self.frames[self.current_frame].putPixel(col, row, colors[0]);
            self.bg_priority.unset(col);
        }
    }

    if (self.regs.ctrl.obj_on) {
        self.drawSpriteLine();
    }
}

fn drawingTick(self: *Display) void {
    if (!self.scanline_drawn) {
        self.drawScanline();
        self.scanline_drawn = true;
    }

    self.dot += 1;
    self.interrupt_line = false;

    if (self.dot >= 80 + 172) {
        self.switchMode(.hblank);
        self.pixel_x = 0;
        self.fetcher.clear();
        self.fifo.clear();
    }
}

fn hblankTick(self: *Display) void {
    self.dot += 1;

    if (self.dot >= dots_per_line) {
        self.dot = 0;
        self.scanline_drawn = false;
        self.incrementLy();

        if (self.regs.ly >= Frame.height) {
            self.switchMode(.vblank);
        } else {
            self.switchMode(.oam_scan);
        }
    } else if (self.dot < 144) {
        self.switchMode(.oam_scan);
    }
}

fn vblankTick(self: *Display) void {
    self.dot += 1;

    if (self.dot >= dots_per_line) {
        self.dot = 0;
        self.incrementLy();

        if (self.regs.ly >= scanlines) {
            self.regs.ly = 0;
            self.window_line = 0;
            self.switchMode(.oam_scan);

            self.frame_num += 1;
            self.current_frame += 1;
            self.current_frame %= self.frames.len;
        }
    }
}

fn switchMode(self: *Display, comptime mode: Mode) void {
    switch (mode) {
        .oam_scan => {
            self.regs.stat.mode = .oam_scan;
            self.statInterrupt(.oam);
        },
        .drawing => {
            self.regs.stat.mode = .drawing;
        },
        .hblank => {
            self.regs.stat.mode = .hblank;
            self.statInterrupt(.hblank);
        },
        .vblank => {
            self.regs.stat.mode = .vblank;
            self.interrupts.request(.vblank);
            self.statInterrupt(.vblank);
        },
    }
}
