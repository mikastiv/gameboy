const Timer = @This();

const Interrupts = @import("Interrupts.zig");

const State = enum { running, reloading, reloaded };

div: u16,
tima: u8,
tma: u8,
tac: packed struct(u8) {
    clock_select: u2,
    enabled: bool,
    _unused: u5 = 0,
},
state: State,
interrupts: *Interrupts,

pub const init: Timer = .{
    .div = 8,
    .tima = 0,
    .tma = 0,
    .tac = .{
        .clock_select = 0,
        .enabled = false,
    },
    .state = .running,
    .interrupts = undefined,
};

pub fn read(self: *const Timer, addr: u16) u8 {
    return switch (addr) {
        0xFF04 => @intCast(self.div >> 8),
        0xFF05 => self.tima,
        0xFF06 => self.tma,
        0xFF07 => @as(u8, @bitCast(self.tac)) | 0xF8,
        else => unreachable,
    };
}

pub fn write(self: *Timer, addr: u16, value: u8) void {
    switch (addr) {
        0xFF04 => {
            const bit_before = self.freqBitOutput();
            self.div = 0;
            const bit_after = self.freqBitOutput();

            if (fallingEdge(bit_before, bit_after)) {
                self.incrementTima();
            }
        },
        0xFF05 => {
            self.tima = value;
            if (self.state == .reloading) {
                self.state = .reloaded;
            }
        },
        0xFF06 => {
            self.tma = value;
            if (self.state == .reloaded) {
                self.tima = value;
            }
        },
        0xFF07 => {
            const bit_before = self.freqBitOutput();
            self.tac = @bitCast(value);
            const bit_after = self.freqBitOutput();

            if (fallingEdge(bit_before, bit_after)) {
                self.incrementTima();
            }
        },
        else => unreachable,
    }
}

pub fn tick(self: *Timer) void {
    switch (self.state) {
        .running => {},
        .reloading => {
            self.tima = self.tma;
            self.interrupts.request(.timer);
            self.state = .reloaded;
        },
        .reloaded => self.state = .running,
    }

    const bit_before = self.freqBitOutput();
    self.div +%= 4;
    const bit_after = self.freqBitOutput();

    if (fallingEdge(bit_before, bit_after)) {
        self.incrementTima();
    }
}

fn freqBitOutput(self: *const Timer) bool {
    const bit_value = self.div & freqBit(self.tac.clock_select) != 0;
    const enabled = self.tac.enabled;

    return bit_value and enabled;
}

fn incrementTima(self: *Timer) void {
    self.tima, const overflow = @addWithOverflow(self.tima, 1);

    if (overflow != 0) {
        self.state = .reloading;
    }
}

fn freqBit(clock_select: u2) u16 {
    return switch (clock_select) {
        0b00 => 1 << 9,
        0b01 => 1 << 3,
        0b10 => 1 << 5,
        0b11 => 1 << 7,
    };
}

fn fallingEdge(before: bool, after: bool) bool {
    return before and !after;
}
