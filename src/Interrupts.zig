const Interrupts = @This();

pub const Flag = enum(u5) {
    vblank = 1 << 0,
    lcd = 1 << 1,
    timer = 1 << 2,
    serial = 1 << 3,
    joypad = 1 << 4,
};

enabled: u5,
requests: u5,

pub const init: Interrupts = .{
    .enabled = 0,
    .requests = 0,
};

pub fn any(self: Interrupts) bool {
    return self.enabled & self.requests != 0;
}

pub fn handled(self: *Interrupts, flag: Flag) void {
    self.requests &= ~@intFromEnum(flag);
}

pub fn highestPriority(self: Interrupts) Flag {
    const queue = self.enabled & self.requests;
    const first = @as(u5, 1) << @ctz(queue);
    return @enumFromInt(first);
}

pub fn handlerAddress(flag: Flag) u16 {
    const bit: u16 = @ctz(@intFromEnum(flag));
    return 0x40 + bit * 0x08;
}
