const std = @import("std");
const Cartridge = @import("Cartridge.zig");
const Interrupts = @import("Interrupts.zig");
const Timer = @import("Timer.zig");

const Bus = @This();

const wram_size = 0x2000;
const wram_mask = wram_size - 1;

const hram_size = 0x80;
const hram_mask = hram_size - 1;

cartridge: Cartridge,
wram: [wram_size]u8,
hram: [hram_size]u8,
interrupts: Interrupts,
timer: Timer,
serial: [2]u8,
cycles: u128,

pub fn init(rom: []const u8) Bus {
    return .{
        .cartridge = Cartridge.init(rom),
        .wram = @splat(0),
        .hram = @splat(0),
        .interrupts = .init,
        .timer = .init,
        .serial = @splat(0),
        .cycles = 0,
    };
}

pub fn peek(self: *const Bus, addr: u16) u8 {
    const value = switch (addr) {
        0x0000...0x7FFF => self.cartridge.read(addr),
        0xA000...0xBFFF => self.cartridge.ramRead(addr),
        0xC000...0xFDFF => self.wram[addr & wram_mask],
        0xFF01 => self.serial[0],
        0xFF02 => self.serial[1],
        0xFF04 => self.timer.read(.div),
        0xFF05 => self.timer.read(.tima),
        0xFF06 => self.timer.read(.tma),
        0xFF07 => self.timer.read(.tac),
        0xFF0F => self.interrupts.requests,
        0xFF80...0xFFFE => self.hram[addr & hram_mask],
        0xFFFF => self.interrupts.enabled,
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

pub fn set(self: *Bus, addr: u16, value: u8) void {
    switch (addr) {
        0x0000...0x7FFF => self.cartridge.write(addr, value),
        0xA000...0xBFFF => self.cartridge.ramWrite(addr, value),
        0xC000...0xFDFF => self.wram[addr & wram_mask] = value,
        0xFF01 => self.serial[0] = value,
        0xFF02 => self.serial[1] = value,
        0xFF04 => self.timer.write(.div, value),
        0xFF05 => self.timer.write(.tima, value),
        0xFF06 => self.timer.write(.tma, value),
        0xFF07 => self.timer.write(.tac, value),
        0xFF0F => self.interrupts.requests = @truncate(value),
        0xFF80...0xFFFE => self.hram[addr & hram_mask] = value,
        0xFFFF => self.interrupts.enabled = @truncate(value),
        else => std.log.debug("unimplemented write ${x:0>4}, ${x:0>2}", .{ addr, value }),
    }
}

pub fn write(self: *Bus, addr: u16, value: u8) void {
    self.tick();
    self.set(addr, value);
}

pub fn tick(self: *Bus) void {
    self.cycles +%= 1;
}
