const Bus = @This();

rom: []const u8,

pub fn init(rom: []const u8) Bus {
    return .{
        .rom = rom,
    };
}

pub fn peek(self: *Bus, address: u16) u8 {
    _ = self; // autofix
    _ = address; // autofix
    return 0;
}

pub fn read(self: *Bus, address: u16) u8 {
    _ = address; // autofix
    self.tick();
    return 0;
}

pub fn write(self: *Bus, address: u16, value: u8) void {
    self.tick();
    _ = address; // autofix
    _ = value; // autofix
}

pub fn tick(self: *Bus) void {
    _ = self; // autofix
}
