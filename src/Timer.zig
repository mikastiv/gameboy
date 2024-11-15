const Interrupts = @import("Interrupts.zig");

const Timer = @This();

pub const Register = enum { div, tima, tma, tac };

div: u16,
tima: u8,
tma: u8,
tac: packed struct(u8) {
    clock_select: u2,
    enabled: bool,
    _unused: u5 = 0,
},
interrupts: *Interrupts,
request_interrupt: bool,

pub const init: Timer = .{
    .div = 0,
    .tima = 0,
    .tma = 0,
    .tac = .{
        .clock_select = 0,
        .enabled = false,
    },
    .interrupts = undefined,
    .request_interrupt = false,
};

pub fn read(self: *const Timer, comptime reg: Register) u8 {
    return switch (reg) {
        .div => @intCast(self.div >> 8),
        // TODO: check tima state
        .tima => self.tima,
        .tma => self.tma,
        .tac => @as(u8, @bitCast(self.tac)) | 0xF8,
    };
}

pub fn write(self: *Timer, comptime reg: Register, value: u8) void {
    switch (reg) {
        .div => {
            if (self.tac.enabled and (self.div & triggerBit(self.tac.clock_select)) != 0) {
                self.incrementTima();
            }
            self.div = 0;
        },
        .tima => {
            // TODO: check tima state
            self.tima = value;
        },
        .tma => {
            self.tma = value;
            // TODO: check tima state
        },
        .tac => self.tac = @bitCast(value),
    }
}

pub fn tick(self: *Timer) void {
    if (self.request_interrupt) {
        self.interrupts.request(.timer);
        self.request_interrupt = false;
    }

    if (self.incrementDiv()) {
        self.incrementTima();
    }
}

fn incrementDiv(self: *Timer) bool {
    const bit_before = self.div & triggerBit(self.tac.clock_select) != 0 and self.tac.enabled;
    self.div +%= 1;
    const bit_after = self.div & triggerBit(self.tac.clock_select) != 0 and self.tac.enabled;

    const falling_edge = bit_before and !bit_after;

    return falling_edge;
}

fn incrementTima(self: *Timer) void {
    self.tima, const overflow = @addWithOverflow(self.tima, 1);

    if (overflow != 0) {
        self.tima = self.tma;
        self.request_interrupt = true;
        // reloading state
    }
}

fn triggerBit(clock_select: u2) u16 {
    return switch (clock_select) {
        0b00 => 1 << 9,
        0b01 => 1 << 3,
        0b10 => 1 << 5,
        0b11 => 1 << 7,
    };
}
