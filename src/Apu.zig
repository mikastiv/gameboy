const Apu = @This();

const ram_size = 0x10;
const ram_mask = ram_size - 1;

ram: [ram_size]u8,

pub const init: Apu = .{
    .ram = @splat(0),
};

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

pub fn ramRead(self: *const Apu, addr: u16) u8 {
    return self.ram[addr & ram_mask];
}

pub fn ramWrite(self: *Apu, addr: u16, value: u8) void {
    self.ram[addr & ram_mask] = value;
}
