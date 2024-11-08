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

pub const init: Timer = .{
    .div = 0,
    .tima = 0,
    .tma = 0,
    .tac = .{
        .clock_select = 0,
        .enabled = false,
    },
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

fn triggerBit(clock_select: u2) u16 {
    return switch (clock_select) {
        0b00 => 1 << 9,
        0b01 => 1 << 3,
        0b10 => 1 << 5,
        0b11 => 1 << 7,
    };
}

fn incrementTima(self: *Timer) void {
    self.tima, const overflow = @addWithOverflow(self.tima, 1);

    if (overflow != 0) {
        self.tima = self.tma;
        // reloading state
    }
}
