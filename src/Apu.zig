const Apu = @This();

pub const init: Apu = .{};

pub fn read(self: *const Apu, addr: u16) u8 {
    _ = self; // autofix
    _ = addr; // autofix
    return 0;
}

pub fn write(self: *Apu, addr: u16, value: u8) void {
    _ = self; // autofix
    _ = addr; // autofix
    _ = value; // autofix
}
