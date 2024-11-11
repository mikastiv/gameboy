const Joypad = @This();

buttons: Buttons,
dpad: DPad,
register: u8,

pub const Buttons = packed struct(u8) {
    a: bool,
    b: bool,
    select: bool,
    start: bool,
    _unused: u4 = 0,

    pub const init: Buttons = .{
        .a = true,
        .b = true,
        .select = true,
        .start = true,
    };
};

pub const DPad = packed struct(u8) {
    right: bool,
    left: bool,
    up: bool,
    down: bool,
    _unused: u4 = 0,

    pub const init: DPad = .{
        .right = true,
        .left = true,
        .up = true,
        .down = true,
    };
};

pub const init: Joypad = .{
    .buttons = .init,
    .dpad = .init,
    .register = 0xCF,
};

const select_dpad = 1 << 4;
const select_buttons = 1 << 5;
const writable = select_buttons | select_dpad;

pub fn read(self: *const Joypad) u8 {
    return self.register;
}

pub fn write(self: *Joypad, value: u8) void {
    self.register = 0xC0 | (value & writable);

    if (self.register & select_buttons != 0)
        self.register |= @bitCast(self.buttons);

    if (self.register & select_dpad != 0)
        self.register |= @bitCast(self.dpad);
}
