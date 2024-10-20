const std = @import("std");
const Cartridge = @import("Cartridge.zig");

const Bus = @This();

const wram_size = 0x2000;
const wram_mask = wram_size - 1;
const WRam = [wram_size]u8;

const hram_size = 0x80;
const hram_mask = hram_size - 1;
const HRam = [hram_size]u8;

cartridge: Cartridge,
wram: WRam,
hram: HRam,

pub fn init(rom: []const u8) Bus {
    return .{
        .cartridge = Cartridge.init(rom),
        .wram = std.mem.zeroes(WRam),
        .hram = std.mem.zeroes(HRam),
    };
}

pub fn peek(self: *Bus, addr: u16) u8 {
    const value = switch (addr) {
        0x0000...0x7FFF => self.cartridge.read(addr),
        0xA000...0xBFFF => self.cartridge.ramRead(addr),
        0xC000...0xFDFF => self.wram[addr & wram_mask],
        0xFF80...0xFFFE => self.hram[addr & hram_mask],
        else => blk: {
            std.log.debug("unimplemented read ${x:0>4}", .{addr});
            break :blk 0;
        },
    };

    return value;
}

pub fn read(self: *Bus, addr: u16) u8 {
    self.tick();

    const value = self.peek(addr);
    return value;
}

pub fn write(self: *Bus, addr: u16, value: u8) void {
    self.tick();

    switch (addr) {
        0x0000...0x7FFF => self.cartridge.write(addr, value),
        0xA000...0xBFFF => self.cartridge.ramWrite(addr, value),
        0xC000...0xFDFF => self.wram[addr & wram_mask] = value,
        0xFF80...0xFFFE => self.hram[addr & hram_mask] = value,
        else => std.log.debug("unimplemented write ${x:0>4}, ${x:0>2}", .{ addr, value }),
    }
}

pub fn tick(self: *Bus) void {
    _ = self; // autofix
}
