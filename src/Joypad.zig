const Joypad = @This();

const Interrupts = @import("Interrupts.zig");

const Buttons = packed struct(u8) {
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

const DPad = packed struct(u8) {
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

buttons: Buttons,
dpad: DPad,
register: u8,
interrupts: *Interrupts,

pub const init: Joypad = .{
    .buttons = .init,
    .dpad = .init,
    .register = 0xCF,
    .interrupts = undefined,
};

pub const Button = enum {
    a,
    b,
    select,
    start,
    right,
    left,
    up,
    down,
};

const select_dpad = 1 << 4;
const select_buttons = 1 << 5;
const writable = select_buttons | select_dpad;

pub fn read(self: *const Joypad) u8 {
    return self.register;
}

pub fn write(self: *Joypad, value: u8) void {
    self.register = value;
    self.update();
}

pub fn setButton(self: *Joypad, button: Button, is_up: bool) void {
    switch (button) {
        .a => self.buttons.a = is_up,
        .b => self.buttons.b = is_up,
        .select => self.buttons.select = is_up,
        .start => self.buttons.start = is_up,
        .right => self.dpad.right = is_up,
        .left => self.dpad.left = is_up,
        .up => self.dpad.up = is_up,
        .down => self.dpad.down = is_up,
    }

    self.update();

    if (!is_up) {
        self.interrupts.request(.joypad);
    }
}

fn update(self: *Joypad) void {
    var result = 0xC0 | (self.register & writable);

    if (self.register & select_buttons == 0) {
        result |= @bitCast(self.buttons);
    }

    if (self.register & select_dpad == 0) {
        result |= @bitCast(self.dpad);

        if (!self.dpad.down and !self.dpad.up) {
            result |= 1 << @bitOffsetOf(DPad, "down");
        }

        if (!self.dpad.left and !self.dpad.right) {
            result |= 1 << @bitOffsetOf(DPad, "left");
        }
    }

    if (self.register & writable == writable)
        result |= 0x0F;

    self.register = result;
}
