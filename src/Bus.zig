const Bus = @This();

pub const init: Bus = .{};

pub fn read(self: *Bus, address: u16) u8 {
    _ = address; // autofix
    _ = self; // autofix
    return 0;
}

pub fn write(self: *Bus, address: u16, value: u8) void {
    _ = self; // autofix
    _ = address; // autofix
    _ = value; // autofix
}

pub fn tick(self: *Bus) void {
    _ = self; // autofix
}
